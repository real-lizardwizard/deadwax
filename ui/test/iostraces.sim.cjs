/**
 * The iPhone app's Up Next is a port of lib/upNext.ts and the queue parts of lib/playQueue.ts, held to the
 * TypeScript by traces recorded from it (ios/scripts/export-traces.cjs) and replayed by the Swift tests
 * (ios/DeadwaxKit/Tests/DeadwaxCoreTests/UpNextTraceTests.swift). This sim is what keeps the traces honest from the
 * web's side: it makes them again in memory and fails when the committed ones differ - so a change to upNext.ts or
 * playQueue.ts (in what they do, or only in their text: the files name the sources' hashes) can't land with the
 * iPhone's port tested against what the TypeScript used to do. The fix is to run the exporter and commit what it
 * writes; that touches ios/, which runs ios.yml's Swift replay, which says whether the port still agrees.
 *
 * Run it with:  node ui/test/iostraces.sim.cjs   (ui/node_modules installed: the exporter compiles with tsc)
 */

const { execFileSync } = require('child_process');
const path = require('path');

const EXPORTER = path.resolve(__dirname, '../../ios/scripts/export-traces.cjs');

let failures = 0;
try {
  const said = execFileSync(process.execPath, [EXPORTER, '--check'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  console.log(`PASS  the iPhone's Up Next traces are what the TypeScript does now\n      ${said.trim()}`);
} catch (error) {
  failures++;
  const said = `${error.stdout ?? ''}${error.stderr ?? ''}`.trim() || String(error.message ?? error);
  console.log(`FAIL  the iPhone's Up Next traces are stale\n${said.split('\n').map((line) => `      ${line}`).join('\n')}`);
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
