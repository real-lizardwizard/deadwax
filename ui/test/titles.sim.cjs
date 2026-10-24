/**
 * A large title's size (2.0.9, the type review): ui/src/lib/titles.ts. An album's name over LONG_TITLE (60) letters
 * is drawn a step smaller - `.pl-hero-title.is-long`, --dw-text-title-long (20px on a phone, 24 on a desktop) - as
 * well as balanced over its lines, so Fiona Apple's 23-word title is four lines on a phone, not five. Letters are
 * code points: an accented or a Japanese name counts each letter once, never each UTF-16 unit.
 *
 * Run it with:  node ui/test/titles.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-titles-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/titles.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

const T = require(path.join(OUT, 'titles.js'));

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

console.log('\na long title, a step smaller');
const PAWN = 'When the Pawn Hits the Conflicts He Thinks Like a King What He Knows Throws the Blows When He Goes to the Fight';
check('the review\'s "about 60"', T.LONG_TITLE, 60);
check('Fiona Apple\'s is long; Dummy, and Godspeed\'s 46 letters, are not',
  [T.isLongTitle(PAWN), T.isLongTitle('Dummy'), T.isLongTitle('Lift Your Skinny Fists Like Antennas to Heaven')], [true, false, false]);
check('exactly 60 letters is not long; 61 is', [T.isLongTitle('x'.repeat(60)), T.isLongTitle('x'.repeat(61))], [false, true]);
check('letters, not UTF-16 units: 40 astral letters (80 units) are not long; 61 accented ones are',
  [T.isLongTitle('\u{1D400}'.repeat(40)), T.isLongTitle('é'.repeat(61))], [false, true]);
check('spaces at either end are not letters', T.isLongTitle(' '.repeat(10) + 'x'.repeat(60) + ' '.repeat(10)), false);
check('nothing yet (the page before the album answers) is not long', [T.isLongTitle(undefined), T.isLongTitle(null), T.isLongTitle('')], [false, false, false]);
check('the class: is-long added to the hero title\'s own', [T.heroTitleClass(PAWN), T.heroTitleClass('Dummy'), T.heroTitleClass(undefined)],
  ['pl-hero-title is-long', 'pl-hero-title', 'pl-hero-title']);

console.log('\ndrawn by every page with a hero title');
const SRC = path.join(UI, 'src');
for (const page of ['player/AlbumPage.tsx', 'app/ReleaseGroupPage.tsx', 'app/PlaylistPage.tsx']) {
  const text = fs.readFileSync(path.join(SRC, page), 'utf8');
  check(`${page}: its title's class from heroTitleClass, of the words it draws`,
    /<h1 class=\{heroTitleClass\(([^)]*)\)\} dir="auto">\{\1(?: \?\? '')?\}<\/h1>/.test(text), true);
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
