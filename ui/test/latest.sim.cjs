/**
 * Only the newest answer counts.
 *
 * Reported as "it's as if it can't handle more than one action at once": a slow answer to an
 * old question was drawn over the answer to the new one. This plays the reported orders of
 * events against BOTH copies of the guard - interface/scripts/latest.mjs (the vanilla half) and
 * ui/src/lib/latest.ts (Preact) - with requests whose answers arrive in whatever order the test
 * says, which is the one thing a real network can't be made to do on demand.
 *
 * Run it with:  node ui/test/latest.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');
const { pathToFileURL } = require('url');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-latest-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/latest.ts', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

/** A request whose answer arrives only when the test says so - or fails, if it was aborted. */
function deferred(signal) {
  let settle;
  const promise = new Promise((resolve, reject) => {
    settle = resolve;
    signal?.addEventListener('abort', () => {
      const error = new Error('The operation was aborted.');
      error.name = 'AbortError';
      reject(error);
    });
  });
  return { promise, answer: (value) => settle(value) };
}

/** What a panel does with a request: draw the answer if it is still the question. */
function panel(L) {
  const guard = L.latestOnly();
  const screen = { shown: 'nothing', errors: [] };
  const ask = (question) => {
    const ticket = guard.begin();
    const request = deferred(ticket.signal);
    request.promise.then(
      (answer) => { if (ticket.current()) screen.shown = answer; },
      (error) => { if (ticket.current() && !L.isAbort(error)) screen.errors.push(error.message); },
    );
    return { ...request, ticket, question };
  };
  return { screen, ask, guard };
}

const tick = () => new Promise((resolve) => setImmediate(resolve));

async function run(name, L) {
  console.log(`\n${name}`);

  {
    const { screen, ask } = panel(L);
    const first = ask('Dummy');
    const second = ask('Third');
    second.answer('Third candidates');
    await tick();
    first.answer('Dummy candidates');
    await tick();
    check('the older search answering LAST is not drawn', screen.shown, 'Third candidates');
    check('...and is no longer current', [first.ticket.current(), second.ticket.current()], [false, true]);
  }

  {
    const { screen, ask } = panel(L);
    const first = ask('Dummy');
    await tick();
    check('a superseded request is aborted, which frees its connection',
      [first.ticket.signal?.aborted, (ask('Third'), first.ticket.signal?.aborted)], [false, true]);
    await tick();
    check('...and its abort is not reported as a failure', screen.errors, []);
  }

  {
    const { screen, ask, guard } = panel(L);
    const first = ask('Dummy');
    guard.supersede();
    first.answer('Dummy candidates');
    await tick();
    check('supersede() without a new request - a cached search, a closed panel - drops it too',
      screen.shown, 'nothing');
  }

  {
    const { screen, ask } = panel(L);
    const only = ask('Dummy');
    only.answer('Dummy candidates');
    await tick();
    check('one request on its own is drawn as it always was', screen.shown, 'Dummy candidates');
  }

  {
    const a = L.latestOnly(), b = L.latestOnly();
    const one = a.begin();
    b.begin();
    check('two guards are independent - the search box does not cancel the candidates panel',
      one.current(), true);
  }
}

(async () => {
  const vanilla = await import(pathToFileURL(path.resolve(__dirname, '../../interface/scripts/latest.mjs')).href);
  const preact = require(path.join(OUT, 'latest.js'));
  await run('interface/scripts/latest.mjs', vanilla);
  await run('ui/src/lib/latest.ts', preact);

  console.log(failures ? `\n${failures} FAILED` : '\nall passed');
  process.exit(failures ? 1 : 0);
})();
