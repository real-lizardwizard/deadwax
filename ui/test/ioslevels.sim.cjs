/**
 * The iPhone app's Normalization, plays and Info words are the web's (notes/ios.md, Phase 1).
 *
 * The phone's Swift ports (ios/DeadwaxKit/Sources/DeadwaxCore: Levels, LevelWords, About, Plays) are held by
 * their tests to vectors in ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/levels/, which
 * ios/scripts/export-level-vectors.cjs writes from what this app's own TypeScript answers - levelFor, relevel,
 * isFlac, describeLevel, aboutLevel, soundRows, formatWords, aboutRows, the play rule and toFixed itself. This
 * runs that script with --check: every vector made again from the TypeScript as it is today and compared byte
 * for byte with the committed files. So a web rule changed here fails here until the vectors are written again
 * - and then the phone's Swift tests fail until the change is ported. (The server's half, gain_for, is
 * tests/test_ios_levels.py's.)
 *
 * Run it with:  TMPDIR=<writable> node ui/test/ioslevels.sim.cjs
 */

const { execFileSync } = require('child_process');
const path = require('path');

const REPO = path.resolve(__dirname, '..', '..');
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-level-vectors.cjs');

let failures = 0;
try {
  const out = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' });
  process.stdout.write(out);
} catch (error) {
  failures++;
  process.stdout.write(error.stdout || '');
  process.stderr.write(error.stderr || '');
  console.log(`  FAIL  the vectors are not what the web's TypeScript answers today (exit ${error.status})`);
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
