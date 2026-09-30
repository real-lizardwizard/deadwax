/**
 * The library explorer's tree, and the track viewer's field choices.
 *
 * A script for the same reason as the others here: there is no JS test runner. The tree's rules
 * about what is on screen are exactly the kind of thing that fails quietly - a filter that opens
 * nothing looks like a filter that found nothing, and a track list built for every album is the
 * 711ms freeze coming back without an error anywhere.
 *
 * Run it with:  node ui/test/tree.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-tree-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/libraryTree.ts', 'src/lib/trackFields.ts', 'src/lib/groupAlbums.ts', 'src/api/library.ts',
  'src/lib/treeWindow.ts',
  '--outDir', OUT, '--module', 'commonjs',
  '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

//? under lib/ because the type-only imports pull src/api into the program, which roots it at src/
const tree = require(path.join(OUT, 'lib/libraryTree.js'));
const fields = require(path.join(OUT, 'lib/trackFields.js'));
const grouping = require(path.join(OUT, 'lib/groupAlbums.js'));
const libraryApi = require(path.join(OUT, 'api/library.js'));
const windowing = require(path.join(OUT, 'lib/treeWindow.js'));

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

const track = (filename, title, disc = null, position = 1) => ({ filename, title, disc, position });
const album = (over) => ({
  path: over.path, artist: over.artist, album: over.album, edition: '', year: '', modified_at: 0,
  first_seen: null, disc_count: 0, tracks: [], ...over,
});
//? built with a NUL, exactly like groupAlbums - a space here is how the old sim missed a real bug
const group = (editions) => ({
  key: `${editions[0].artist.toLowerCase()}\u0000${editions[0].album.toLowerCase()}`,
  artist: editions[0].artist, album: editions[0].album, year: editions[0].year, yearRange: '',
  editions, needsAttention: 0, issues: [],
});

const wall = album({
  path: 'Pink Floyd/The Wall (1979)', artist: 'Pink Floyd', album: 'The Wall', year: '1979',
  disc_count: 2, modified_at: 1000,
  tracks: [track('a', 'In the Flesh?', 1, 1), track('b', 'Mother', 1, 2),
           track('c', 'Hey You', 2, 1), track('d', 'Vera', 2, 2)],
});
const dsotm = album({
  path: 'Pink Floyd/DSOTM (1973)', artist: 'Pink Floyd', album: 'The Dark Side of the Moon',
  year: '1973', modified_at: 3000, tracks: [track('e', 'Speak to Me'), track('f', 'Breathe')],
});
const standard = album({
  path: 'Tame Impala/The Slow Rush (2020)', artist: 'Tame Impala', album: 'The Slow Rush',
  year: '2020', modified_at: 2000, tracks: [track('g', 'One More Year')],
});
const deluxe = album({
  path: 'Tame Impala/The Slow Rush (2020) [Deluxe]', artist: 'Tame Impala', album: 'The Slow Rush',
  edition: 'Deluxe', year: '2021', modified_at: 5000,
  tracks: [track('h', 'One More Year'), track('i', 'Breathe Deeper')],
});
const undated = album({ path: 'aphex/x', artist: 'aphex twin', album: 'Untitled', tracks: [track('j', 'Xtal')] });

const groups = [group([wall]), group([dsotm]), group([standard, deluxe]), group([undated])];
const never = () => false;
const artists = tree.groupArtists(groups, never);
const layout = { by: 'artist', artists };

const state = (over = {}) => ({
  expanded: new Set(), closedWhileFiltering: new Set(), filtering: false, trackMatches: new Set(), ...over,
});
const shape = (rows) => rows.map((r) => `${r.kind}${r.level}:${
  r.kind === 'artist' ? r.node.artist : r.kind === 'group' ? r.group.album
  : r.kind === 'edition' ? r.album.edition || 'Standard' : r.kind === 'disc' ? r.disc
  : r.kind === 'heading' ? r.label : r.track.title}`);

console.log('\nordering');
check('artists A-Z, case-insensitively', artists.map((a) => a.artist), ['aphex twin', 'Pink Floyd', 'Tame Impala']);
check("an artist's albums run by year", artists[1].groups.map((g) => g.album), ['The Dark Side of the Moon', 'The Wall']);
check('Z-A reverses the artists but not a discography',
      tree.groupArtists(groups, never, 'desc').map((a) => a.artist), ['Tame Impala', 'Pink Floyd', 'aphex twin']);

console.log('\nnothing exists below a closed node');
check('closed: only artists', shape(tree.visibleRows(layout, state())),
      ['artist1:aphex twin', 'artist1:Pink Floyd', 'artist1:Tame Impala']);
check('no track row anywhere until an album is opened',
      tree.visibleRows(layout, state({ expanded: new Set([tree.artistNodeId('Pink Floyd')]) }))
        .filter((r) => r.kind === 'track').length, 0);

console.log('\nopening walks down a level at a time');
const floydOpen = state({ expanded: new Set([tree.artistNodeId('Pink Floyd'), tree.groupNodeId(groups[0])]) });
//? from 2: aphex twin and Pink Floyd themselves come first
check('a multi-disc album splits by disc', shape(tree.visibleRows(layout, floydOpen)).slice(2, 10), [
  'group2:The Dark Side of the Moon', 'group2:The Wall',
  'disc3:1', 'track3:In the Flesh?', 'track3:Mother', 'disc3:2', 'track3:Hey You', 'track3:Vera',
]);
{
  //? a disc's own title rides on its divider (v1.1.0), from the scan's per-album map - keyed by
  //? the disc as a string, as JSON hands it over; an untitled disc carries ''
  const titled = { ...wall, disc_titles: { '2': 'Live at Wembley' } };
  const titledGroups = [group([titled]), ...groups.slice(1)];
  const titledLayout = { by: 'artist', artists: tree.groupArtists(titledGroups, never) };
  const titledOpen = state({ expanded: new Set([tree.artistNodeId('Pink Floyd'), tree.groupNodeId(titledGroups[0])]) });
  check('a titled disc carries its title, an untitled one none',
        tree.visibleRows(titledLayout, titledOpen).filter((r) => r.kind === 'disc').map((r) => [r.disc, r.title]),
        [[1, ''], [2, 'Live at Wembley']]);
  check('an album the scan gave no titles to has none', [tree.discTitle(wall, 1), tree.discTitle(wall, 2)], ['', '']);
}
const tameOpen = state({ expanded: new Set([tree.artistNodeId('Tame Impala'), tree.groupNodeId(groups[2])]) });
check('an album with several editions opens to its editions, not its tracks',
      shape(tree.visibleRows(layout, tameOpen)).filter((s) => !s.startsWith('artist')),
      ['group2:The Slow Rush', 'edition3:Standard', 'edition3:Deluxe']);

console.log('\nfiltering opens what it found');
check('artists open by themselves while filtering',
      shape(tree.visibleRows(layout, state({ filtering: true }))).filter((s) => s.startsWith('group')).length, 4);
check('...unless you closed one again',
      shape(tree.visibleRows(layout, state({
        filtering: true, closedWhileFiltering: new Set([tree.artistNodeId('Pink Floyd')]),
      }))).filter((s) => s.startsWith('group')).length, 2);

const heyYou = tree.trackNodeId(wall, wall.tracks[2]);
const matched = tree.visibleRows(layout, state({ filtering: true, trackMatches: new Set([heyYou]) }));
check('a song match opens its album and shows just that song',
      shape(matched).filter((s) => s.startsWith('track') || s.startsWith('disc')), ['disc3:2', 'track3:Hey You']);
check('and marks it as the match', matched.find((r) => r.id === heyYou)?.match, true);
check('opening that album by hand shows all of it again',
      tree.visibleRows(layout, state({
        filtering: true, trackMatches: new Set([heyYou]), expanded: new Set([tree.groupNodeId(groups[0])]),
      })).filter((r) => r.kind === 'track' && r.album === wall).length, 4);

console.log('\narranged by something other than artist');
const byAlbum = tree.arrange(groups, 'album', 'asc', never);
check('album sort lists albums, with no artist level',
      shape(tree.visibleRows(byAlbum, state())),
      ['heading1:T', 'group1:The Dark Side of the Moon', 'group1:The Slow Rush', 'group1:The Wall',
       'heading1:U', 'group1:Untitled']);
check('and every album row says whose it is',
      tree.visibleRows(byAlbum, state()).filter((r) => r.kind === 'group').every((r) => r.withArtist), true);

const released = (direction) => tree.arrange(groups, 'released', direction, never).groups.map((g) => g.album);
check('release date, oldest first', released('asc'),
      ['The Dark Side of the Moon', 'The Wall', 'The Slow Rush', 'Untitled']);
check('release date, newest first - and the undated album still sinks', released('desc'),
      ['The Slow Rush', 'The Wall', 'The Dark Side of the Moon', 'Untitled']);
check('headed by year', tree.visibleRows(tree.arrange(groups, 'released', 'asc', never), state())
      .filter((r) => r.kind === 'heading').map((r) => r.label), ['1973', '1979', '2020', 'Undated']);

check('date added, newest first: a new deluxe press brings its album to the top',
      tree.arrange(groups, 'added', 'desc', never).groups.map((g) => g.album),
      ['The Slow Rush', 'The Dark Side of the Moon', 'The Wall', 'Untitled']);
check('the earlier clock wins: first seen before the folder changed',
      tree.albumAddedAt(album({ path: 'p', first_seen: '1970-01-01T00:08:20Z', modified_at: 1000 })), 500);
check('...and the folder date when it is the earlier one (an album from before install)',
      tree.albumAddedAt(album({ path: 'p', first_seen: '1970-01-01T01:00:00Z', modified_at: 1000 })), 1000);

const openInAlbumLayout = tree.visibleRows(byAlbum, state({ expanded: new Set([tree.groupNodeId(groups[0])]) }));
check('an opened album in a flat arrangement nests one level in',
      shape(openInAlbumLayout).filter((s) => s.startsWith('disc') || s.startsWith('track')).slice(0, 3),
      ['disc2:1', 'track2:In the Flesh?', 'track2:Mother']);

console.log('\nwhat a node is, and what must open to reach it');
const index = tree.indexTree(artists);
check('a single-edition album IS its release', index.get(tree.groupNodeId(groups[1]))?.kind, 'album');
check('a multi-edition album is the group as a whole', index.get(tree.groupNodeId(groups[2]))?.kind, 'group');
check('a track in an edition needs artist, album and edition open',
      tree.ancestorsOf(tree.trackNodeId(deluxe, deluxe.tracks[1]), layout),
      [tree.artistNodeId('Tame Impala'), tree.groupNodeId(groups[2]), tree.editionNodeId(deluxe)]);
check('a track on a single-edition album needs artist and album',
      tree.ancestorsOf(heyYou, layout), [tree.artistNodeId('Pink Floyd'), tree.groupNodeId(groups[0])]);
check('arranged by album there is no artist to open', tree.ancestorsOf(heyYou, byAlbum), [tree.groupNodeId(groups[0])]);

console.log('\nfield choices outlive the version that wrote them');
const initial = fields.TRACK_FIELDS.filter((f) => f.initial).map((f) => f.id);
check('nothing saved: the defaults', fields.reconcileVisible(null), initial);
check('a removed field is dropped, not kept as a dead column',
      fields.reconcileVisible({ visible: ['number', 'gone'], seen: ['number', 'gone'] }).includes('gone'), false);
const everyId = fields.TRACK_FIELDS.map((f) => f.id);
check('a field you turned off stays off',
      fields.reconcileVisible({ visible: ['number'], seen: everyId }), ['number']);
check('a field added since you chose takes its own default rather than staying hidden',
      fields.reconcileVisible({ visible: ['number'], seen: everyId.filter((id) => id !== 'bitrate') }),
      ['number', 'bitrate']);

console.log('\nwhat an album\'s folders are called (v0.9.13)');
{
  const ed = (split, count) => ({ split_discs: split, edition_count: count });
  check('ordinary editions', grouping.folderSummary([ed(false, 2), ed(false, 2)]).label, '2 editions');
  const split = (over) => ({ edition: '', disc_label: 'Disc 4', discs: [4], ...over });
  check('a folder of one titled disc says its title (v1.1.0)',
    grouping.editionName(split({ disc_titles: { '4': 'Live at Wembley' } })), 'Disc 4 · Live at Wembley');
  check('...after its edition, when it has one',
    grouping.editionName(split({ edition: 'Deluxe', disc_titles: { '4': 'Live at Wembley' } })), 'Deluxe · Disc 4 · Live at Wembley');
  check('an untitled disc is just its number', grouping.editionName(split({})), 'Disc 4');
  check('a folder of several discs names none of their titles',
    grouping.editionName(split({ disc_label: 'Discs 1, 2', discs: [1, 2], disc_titles: { '1': 'A', '2': 'B' } })), 'Discs 1, 2');
  check('the discs of one release are disc folders, not editions',
    grouping.folderSummary([ed(true, 1), ed(true, 1)]).label, '2 disc folders');
  check('a split release beside a real second edition',
    grouping.folderSummary([ed(true, 2), ed(true, 2), ed(false, 2)]).label, '2 editions · split discs');
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

console.log('\nonly the rows in view are drawn (v0.9.30)');
{
  const heading = (label) => ({ kind: 'heading', id: null, level: 1, parent: null, label });
  const artist = (id) => ({ kind: 'artist', id, level: 1, parent: null, open: true, node: {} });
  const track = (id, parent) => ({ kind: 'track', id, level: 2, parent, album: {}, track: {}, match: false });
  const rows = [heading('A'), artist('a'), track('t1', 'a'), track('t2', 'a'), heading('B'), artist('b'), track('t3', 'b')];
  const heights = { 'heading-first': 23.5, heading: 31.5, artist: 24, track: 24 };

  const offsets = windowing.rowOffsets(rows, heights, 24);
  check('every row starts where the one above it ends, the first heading its own height',
    Array.from(offsets), [0, 23.5, 47.5, 71.5, 95.5, 127, 151, 175]);
  check('a kind not measured yet takes the fallback', Array.from(windowing.rowOffsets([artist('x')], {}, 26)), [0, 26]);

  check('the rows overlapping the view, and no more', windowing.visibleSpan(offsets, 50, 40, 0), [2, 4]);
  check('a row straddling the bottom edge is in', windowing.visibleSpan(offsets, 0, 48, 0), [0, 3]);
  check('the margin widens it both ways', windowing.visibleSpan(offsets, 60, 10, 30), [1, 5]);
  check('scrolled past the end: nothing', windowing.visibleSpan(offsets, 1000, 100, 0), [7, 7]);
  check('an empty tree draws nothing', windowing.visibleSpan(new Float64Array(1), 0, 500, 600), [0, 0]);

  check('a pinned row far away is drawn too, in order', windowing.rowsToDraw([2, 4], [6, 3, -1, 99], 7), [2, 3, 6]);
  check('with nothing pinned outside, just the span', windowing.rowsToDraw([1, 3], [2], 7), [1, 2]);

  check('each item knows its place among its siblings',
    windowing.siblingPositions(rows).map((p) => `${p.posinset}/${p.setsize}`),
    ['0/0', '1/2', '1/2', '2/2', '0/0', '2/2', '1/1']);
}

console.log(failures ? `\n${failures} FAILED\n` : '\nall passed\n');
process.exit(failures ? 1 : 0);
