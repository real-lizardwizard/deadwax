/**
 * The iPhone app's Up Next and its resume are ports of the web app's: lib/upNext.ts and the queue parts of
 * lib/playQueue.ts, and lib/resume.ts (the snapshot the two write and read, what is put back, when it saves). They
 * are held to the TypeScript by traces recorded from it (ios/scripts/export-traces.cjs) and replayed by the Swift
 * tests (ios/DeadwaxKit/Tests/DeadwaxCoreTests/UpNextTraceTests.swift, Resume*Tests.swift). This sim is what keeps
 * the traces honest from the web's side: it makes them again in memory and fails when the committed ones differ - so
 * a change to upNext.ts, playQueue.ts or resume.ts (in what they do, or only in their text: the files name the
 * sources' hashes), or to the pieces of useResume.ts, persisted.ts, api.ts and useShuffleFeed.ts the phone mirrors,
 * can't land with the iPhone's port tested against what the TypeScript used to do. A queue saved on one is put back
 * by the other, so a snapshot the web writes differently from the phone is a queue lost. The fix is to run the
 * exporter and commit what it writes; that touches ios/, which runs ios.yml's Swift replay, which says whether the
 * ports still agree. The two controllers replay nothing - QueueController.swift ports usePlayer.ts's queue rules and
 * ResumeController.swift useResume.ts's createResume, by hand - so the pieces of those they port are hashed too,
 * function by function: a change to one fails here naming the piece and the Swift file, to be ported before the
 * exporter is run.
 *
 * Run it with:  node ui/test/iostraces.sim.cjs   (ui/node_modules installed: the exporter compiles with tsc)
 */

const { execFileSync } = require('child_process');
const path = require('path');

const EXPORTER = path.resolve(__dirname, '../../ios/scripts/export-traces.cjs');

let failures = 0;
try {
  const said = execFileSync(process.execPath, [EXPORTER, '--check'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  console.log(`PASS  the iPhone's Up Next and resume traces are what the TypeScript does now\n      ${said.trim()}`);
} catch (error) {
  failures++;
  const said = `${error.stdout ?? ''}${error.stderr ?? ''}`.trim() || String(error.message ?? error);
  console.log(`FAIL  the iPhone's Up Next and resume traces are stale\n${said.split('\n').map((line) => `      ${line}`).join('\n')}`);
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
