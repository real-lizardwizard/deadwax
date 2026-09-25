/**
 * Editing tags by hand, and arranging the track viewer's columns.
 *
 * A script for the same reason as the others here: there is no JS test runner. Both halves fail
 * quietly. A mass edit that sends a field you never touched overwrites every track's own value
 * and looks exactly like one that didn't; a column order that loses a field when a later
 * version adds one simply stops showing it, with nothing to say it exists.
 *
 * Run it with:  node ui/test/tags.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-tags-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/tagEdit.ts', 'src/lib/trackFields.ts', 'src/lib/release.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

//? under lib/ because the type-only imports pull src/api into the program, which roots it at src/
const tags = require(path.join(OUT, 'lib/tagEdit.js'));
const fields = require(path.join(OUT, 'lib/trackFields.js'));
const release = require(path.join(OUT, 'lib/release.js'));

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

const file = (filename, tagsOf) => ({ filename, tags: tagsOf, position: null, disc: null });

console.log('\nwhat a selection holds in each field');
const a = file('01.flac', { genre: 'Rock', album: 'Jackpot Juicer' });
const b = file('02.flac', { genre: 'Metal', album: 'Jackpot Juicer' });
const c = file('03.flac', { album: 'Jackpot Juicer' });
check('one value across every file is shown', tags.sharedValue([a, b], 'album'), { value: 'Jackpot Juicer', mixed: false });
check('different values are mixed, and show nothing', tags.sharedValue([a, b], 'genre'), { value: '', mixed: true });
check('a tag only some files have is mixed too', tags.sharedValue([a, c], 'genre'), { value: '', mixed: true });
check('a tag none of them has is simply empty', tags.sharedValue([a, b], 'composer'), { value: '', mixed: false });
check('no files: nothing to share', tags.sharedValue([], 'genre'), { value: '', mixed: false });

console.log('\nwhat is sent');
check('nothing edited: nothing sent', tags.buildEdits(['01.flac', '02.flac'], {}), []);
check('only the edited field, to every file, trimmed',
      tags.buildEdits(['01.flac', '02.flac'], { discnumber: ' 1 ' }),
      [{ filename: '01.flac', tags: { discnumber: '1' } }, { filename: '02.flac', tags: { discnumber: '1' } }]);
check('a field emptied on purpose is sent empty, which removes the tag',
      tags.buildEdits(['01.flac'], { genre: '' }), [{ filename: '01.flac', tags: { genre: '' } }]);
const edits = tags.buildEdits(['01.flac', '02.flac'], { genre: 'Rock' });
edits[0].tags.genre = 'changed';
check('each file gets its own copy of the tags', edits[1].tags.genre, 'Rock');

console.log('\nwhat is refused as you type (mirrors validate_tag in src/track_tags.py)');
check('a track number of a set', tags.tagProblem('tracknumber', '3/12'), null);
check('not a track number', tags.tagProblem('tracknumber', 'three') !== null, true);
check('a whole date', tags.tagProblem('date', '2022-07-29'), null);
check('not a date', tags.tagProblem('date', 'July 2022') !== null, true);
check('empty is fine - it removes the tag', tags.tagProblem('discnumber', ''), null);
check('a title can say anything on one line', tags.tagProblem('title', 'Pray to God for Your Mother'), null);
check('a line break or any other control character is refused',
      ['two\nlines', 'a\u0000b', 'a\u001fb', 'a\u007fb'].map((text) => tags.tagProblem('title', text) !== null),
      [true, true, true, true]);
check('...but a backslash, an x and a zero are ordinary text', tags.tagProblem('title', 'AC\\DC x 10'), null);

console.log('\nticking tracks');
const order = ['01', '02', '03', '04', '05'];
let state = tags.tickTracks(order, new Set(), null, '02', false);
check('a click ticks one', [...state.files], ['02']);
state = tags.tickTracks(order, state.files, state.anchor, '04', true);
check('a shift-click ticks the run between', [...state.files].sort(), ['02', '03', '04']);
state = tags.tickTracks(order, state.files, state.anchor, '03', true);
check('a shift-click on a ticked box unticks the run back to the last click', [...state.files].sort(), ['02']);
state = tags.tickTracks(order, state.files, state.anchor, '02', false);
check('a plain click on a ticked box unticks just that one', [...state.files], []);
check('shift with nothing clicked before is an ordinary click',
      [...tags.tickTracks(order, new Set(), null, '03', true).files], ['03']);

console.log('\nthe disc column: untagged reads as disc 1, and says so');
const disc = fields.fieldById('disc');
const row = (scanDisc, details) => ({ track: { disc: scanDisc, position: 1 }, details });
check('no disc tag shows 1', disc.value(row(null, undefined)), '1');
check('...dimmed as a default, with the reason', disc.inferred(row(null, undefined)) !== null, true);
check('a tagged disc is itself', disc.value(row(2, undefined)), '2');
check('...and not a default', disc.inferred(row(2, undefined)), null);
check('the file, once read, wins over a stale scan', disc.value(row(2, { disc: null, position: 1 })), '1');

console.log('\narranging the columns');
const defaults = fields.defaultOrder();
check('number and disc come before the title, as on a sleeve', defaults.slice(0, 3), ['number', 'disc', 'title']);
check('every field has a place', defaults.length, fields.TRACK_FIELDS.length + 1);
check('nothing saved: the default order', fields.reconcileOrder(undefined), defaults);
check('an older blob with no order: the default', fields.reconcileOrder([]), defaults);
const moved = fields.moveColumn(defaults, 'title', 'number');
check('a column dragged to the front goes first', moved.slice(0, 3), ['title', 'number', 'disc']);
check('dropping past the last column puts it last', fields.moveColumn(defaults, 'number', null).at(-1), 'number');
check('dropping a column on itself changes nothing', fields.moveColumn(defaults, 'disc', 'disc'), defaults);
check('dropping just before its own neighbour changes nothing', fields.moveColumn(defaults, 'number', 'disc'), defaults);
check('a saved order keeps its arrangement', fields.reconcileOrder(moved), moved);
check('a column that no longer exists is dropped', fields.reconcileOrder([...moved, 'gone']).includes('gone'), false);
const restored = fields.reconcileOrder(moved.filter((id) => id !== 'bitrate'));
check('a column added since you arranged them turns up beside its default neighbour',
      restored.indexOf('bitrate'), restored.indexOf(defaults[defaults.indexOf('bitrate') - 1]) + 1);
check('...and nothing is lost or doubled', [...new Set(restored)].length, defaults.length);
check('the title is always drawn', fields.visibleColumns(defaults, ['number']), ['number', 'title']);
check('hidden columns keep their place in the order', fields.visibleColumns(moved, ['disc', 'number']),
      ['title', 'number', 'disc']);

console.log('\nsizing the columns');
check('untouched columns keep their own sizes',
      fields.columnLayout(['number', 'title'], {}, ['2.4em']).template, '2.4em 2.6em minmax(10em, 2fr)');
const sized = fields.columnLayout(['number', 'title'], { title: 300 }, ['2.4em']);
check('a dragged column is exactly that wide', sized.template, '2.4em 2.6em 300px');
check('...and counts towards the table\'s minimum in px', sized.minWidth.includes('300px'), true);
check('the minimum is exactly the columns\' own minimums, with no slack for a lone flexible column to swallow',
      fields.columnLayout(['number', 'title'], {}, ['2.4em']).minWidth, 'calc(15em + 0px)');
check('a column that stretches is flexible - a resize has to pin those to its left',
      [fields.isFlexible('title'), fields.isFlexible('artist')], [true, true]);
check('...and one with a size of its own is not, so it never moves under the drag',
      [fields.isFlexible('number'), fields.isFlexible('length')], [false, false]);
check('a column nobody has heard of takes the flexible default', fields.isFlexible('nonesuch'), true);
check('the title\'s track is the one the layout draws it with', fields.columnSize('title'), fields.TITLE_WIDTH);
check('a width below the minimum is raised to it', fields.clampWidth(4), fields.MIN_COLUMN_PX);
check('saved widths for columns that are gone are dropped',
      fields.reconcileWidths({ title: 200, gone: 90 }), { title: 200 });

console.log('\nartist credits (mirrors credit_name/credit_ids in src/artists.py)');
const SPLIT = [
  { name: 'Dance Gavin Dance', joinphrase: ' / ', artist: { id: 'id-dgd' } },
  { name: 'Tilian', joinphrase: '', artist: { id: 'id-tilian' } },
];
const FEAT = [
  { name: 'Jay-Z', joinphrase: ' feat. ', artist: { id: 'id-jay' } },
  { name: 'Linkin Park', artist: { id: 'id-lp' } },
];
check('a split reads with the join phrase MusicBrainz gave it',
      release.creditName(SPLIT), 'Dance Gavin Dance / Tilian');
check('so does a guest spot', release.creditName(FEAT), 'Jay-Z feat. Linkin Park');
check('one artist is just their name', release.creditName([{ name: 'Portishead' }]), 'Portishead');
check('nothing credited is nothing, not "N/A"', release.creditName(undefined), '');
check('every id, in the order credited', release.creditIds(SPLIT), ['id-dgd', 'id-tilian']);
check('the same artist credited twice is one id',
      release.creditIds([{ name: 'A', artist: { id: 'x' } }, { name: 'A again', artist: { id: 'x' } }]), ['x']);

console.log('\nan instrumental release is an edition (the third copy of the vocabulary)');
check('"Jackpot Juicer (instrumental)" is tagged INSTRUMENTAL',
      release.detectEditionTags({ id: 'x', title: 'Jackpot Juicer (instrumental)', disambiguation: '' }),
      ['INSTRUMENTAL']);
check('the ordinary album is not',
      release.detectEditionTags({ id: 'y', title: 'Jackpot Juicer', disambiguation: '' }), []);

console.log(failures ? `\n${failures} FAILED\n` : '\nall passed\n');
process.exit(failures ? 1 : 0);
