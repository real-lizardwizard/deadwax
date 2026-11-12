/**
 * The iPhone app's turntable is a port of the web's: lib/platter.ts, lib/turntable.ts, lib/playSpeed.ts,
 * lib/deckClock.ts's pointer samples, lib/debugRows.ts's turntable rows, player/deck.ts's rules, lib/deckVoice.ts's
 * voice and Turntable.tsx's handlers (notes/ios-specs/turntable.md, slice 1). They are held to the TypeScript by
 * vectors and traces recorded from it (ios/scripts/export-deck-vectors.cjs, Fixtures/deck/) and replayed by the
 * Swift tests - the voice bit for bit. This sim keeps the fixtures honest from the web's side: it makes them again in
 * memory and fails when the committed ones differ, so a change to any of those files (in what it does, or only in its
 * text: each fixture names its sources' hashes), or to the words and labels read out of Turntable.tsx, SpeedFader.tsx,
 * SpeedChip.tsx, LookChoice.tsx, WindDownChoice.tsx and You.tsx, or to theme.css's turntable tokens, can't land with
 * the iPhone's port tested against what the TypeScript used to do. The fix is to port the change to the Swift, run
 * the exporter and commit what it writes. It also holds the folder to its 3 MB budget (the spec's 7.0).
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosdeck.sim.cjs   (ui/node_modules installed: the exporter compiles with tsc)
 */

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const EXPORTER = path.resolve(__dirname, '../../ios/scripts/export-deck-vectors.cjs');
const FIXTURES = path.resolve(__dirname, '../../ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/deck');
const BUDGET = 3 * 1024 * 1024;

let failures = 0;
try {
  const said = execFileSync(process.execPath, [EXPORTER, '--check'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  console.log(`PASS  the iPhone's turntable fixtures are what the TypeScript does now\n      ${said.trim()}`);
} catch (error) {
  failures++;
  const said = `${error.stdout ?? ''}${error.stderr ?? ''}`.trim() || String(error.message ?? error);
  console.log(`FAIL  the iPhone's turntable fixtures are stale\n${said.split('\n').map((line) => `      ${line}`).join('\n')}`);
}

function size(at) {
  if (!fs.existsSync(at)) return 0;
  const stat = fs.statSync(at);
  if (!stat.isDirectory()) return stat.size;
  return fs.readdirSync(at).reduce((sum, name) => sum + size(path.join(at, name)), 0);
}
const total = size(FIXTURES);
if (total > 0 && total <= BUDGET) {
  console.log(`PASS  Fixtures/deck is ${Math.round(total / 1024)} KB, within its ${BUDGET / 1024} KB budget`);
} else {
  failures++;
  console.log(`FAIL  Fixtures/deck is ${Math.round(total / 1024)} KB - ${total ? `over its ${BUDGET / 1024} KB budget` : 'missing'}`);
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
