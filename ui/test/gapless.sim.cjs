/**
 * The gapless switch's decisions: what the standby element gets ready, when a song change hands
 * over to it and when it goes the one-element way, which element's events count, what goes into
 * memory, which element is playing after what, and what the readout says.
 *
 * A script for the same reason as the other sims: there is no JS test runner here. What it pins
 * is behaviour a person notices only on the phone, in a pocket - a handover to the wrong song, a
 * standby's 'pause' stopping the lock screen, a song that fails from memory skipped when
 * Navidrome would have played it, a 300 MB hi-res file held in memory until iOS reloads the page,
 * a standby downloading for AirPlay where it can never be used, or a mode that stops the music when
 * it can't do its job instead of falling back to the one element that always worked. And a readout
 * that times the wrong thing - 'playing' rather than the clock, a minute of silence as a gap, a
 * ready element called "had to load" - would send the one test on the phone the wrong way.
 *
 * Run it with:  node ui/test/gapless.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-gapless-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/gapless.ts', 'src/lib/playQueue.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

const {
  standbyPlan, handoverDecision, memoryPlan, overMemoryMax, routeEvent, activeAfter, afterPlaybackFailure,
  startChange, gapReading, clockStep, withReading, describeHow, describeGaps,
  MEMORY_MAX_BYTES, PRELOAD_DELAY_MS, GAPS_KEPT, CHANGE_MAX_MS,
} = require(path.join(OUT, 'lib/gapless.js'));
const {
  MEDIA_ERR_ABORTED, MEDIA_ERR_NETWORK, MEDIA_ERR_DECODE, MEDIA_ERR_SRC_NOT_SUPPORTED,
} = require(path.join(OUT, 'lib/playQueue.js'));

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

const track = (id) => ({
  id, title: `song ${id}`, artist: 'a', album: 'b', albumId: 'al', coverArt: null,
  duration: 200, contentType: 'audio/flac', suffix: 'flac',
});
const album = ['1', '2', '3', '4'].map(track);
const at = (index, tracks = album) => ({ tracks, index });
const standby = (index, id, fields = {}) => ({ index, id, stage: 'memory', failed: false, ...fields });

/* ========================================================================== */
console.log('\nwhat the standby gets ready');

check('switch off, nothing held: nothing to do', standbyPlan(at(0), false, null), { kind: 'none' });
check('switch off with something held: let it go', standbyPlan(at(0), false, standby(1, '2')).kind, 'clear');
check('the song after the one playing', standbyPlan(at(0), true, null), { kind: 'load', index: 1, track: album[1] });
check('already holding it: keep it', standbyPlan(at(0), true, standby(1, '2')), { kind: 'keep' });
check('still downloading it: keep it', standbyPlan(at(0), true, standby(1, '2', { stage: 'fetching' })).kind, 'keep');
//? getting a song that failed again would fail again, on every 'playing' - its turn deals with it
check('holding it but it failed: keep it, not a download loop', standbyPlan(at(0), true, standby(1, '2', { failed: true })).kind, 'keep');
check('after "next", the old next is not the new next', standbyPlan(at(1), true, standby(1, '2')), { kind: 'load', index: 2, track: album[2] });
check('after "previous", neither', standbyPlan(at(0), true, standby(2, '3')).kind, 'load');
{
  //? a new album at the same position: the same index holds a different song
  const other = ['x', 'y', 'z'].map(track);
  check('a new album with the same index: not the same song', standbyPlan(at(0, other), true, standby(1, '2')).kind, 'load');
}
check('the last song: nothing after it, let go of what is held', standbyPlan(at(3), true, standby(3, '4')).kind, 'clear');
check('the last song with nothing held: nothing to do', standbyPlan(at(3), true, null).kind, 'none');
check('an empty queue', standbyPlan({ tracks: [], index: -1 }, true, null).kind, 'none');
//? a handover never happens on AirPlay, so a standby there would only download every song for nothing
check('AirPlaying: nothing got ready', standbyPlan(at(0), true, null, true), { kind: 'none' });
check('AirPlaying with the next song held: let it go', standbyPlan(at(0), true, standby(1, '2'), true).kind, 'clear');
check('AirPlaying while it downloads: let it go', standbyPlan(at(0), true, standby(1, '2', { stage: 'fetching' }), true).kind, 'clear');
check('AirPlay over: the next song again', standbyPlan(at(0), true, null, false), { kind: 'load', index: 1, track: album[1] });

/* ========================================================================== */
console.log('\nhand over, or the one-element way');

const ask = (fields) => handoverDecision({
  enabled: true, standby: standby(1, '2'), queue: at(1), index: 1, autoplay: true, wireless: false, ...fields,
});

check('holding the next song in memory: hand over', ask({}), { kind: 'handover', source: 'memory' });
check('holding its address: hand over, streamed', ask({ standby: standby(1, '2', { stage: 'stream' }) }), { kind: 'handover', source: 'stream' });
check('switch off: one element, as always', ask({ enabled: false }), { kind: 'same element', reason: 'off' });
check('"next" while paused: one element', ask({ autoplay: false }).reason, 'paused');
check('sending to AirPlay: one element', ask({ wireless: true }).reason, 'airplay');
check('nothing got ready: one element', ask({ standby: null }).reason, 'nothing ready');
check('another song got ready: one element', ask({ standby: standby(2, '3') }).reason, 'another song ready');
check('the right position but another song (a new queue): one element', ask({ standby: standby(1, 'x') }).reason, 'another song ready');
//? abandoning the download for the one element would ask for the song again there all the same
check('its download not finished: hand over by address', ask({ standby: standby(1, '2', { stage: 'fetching' }) }), { kind: 'handover', source: 'unfinished' });
check('another song still downloading: one element', ask({ standby: standby(2, '3', { stage: 'fetching' }) }).reason, 'another song ready');
check('the next song still downloading, but AirPlay: one element', ask({ standby: standby(1, '2', { stage: 'fetching' }), wireless: true }).reason, 'airplay');
check('the next song still downloading, but paused: one element', ask({ standby: standby(1, '2', { stage: 'fetching' }), autoplay: false }).reason, 'paused');
check('its element failed to load it: one element', ask({ standby: standby(1, '2', { failed: true }) }).reason, 'failed to get ready');
check('off wins over everything else', ask({ enabled: false, wireless: true, standby: null }).reason, 'off');

/* ========================================================================== */
console.log('\nwhat goes into memory');

const mem = (fields) => memoryPlan({
  ok: true, contentType: 'audio/flac', contentLength: 30e6, raw: true, ...fields,
});

check('a 30 MB FLAC as it is: memory', mem({}), 'memory');
check('exactly at the limit: memory', mem({ contentLength: MEMORY_MAX_BYTES }), 'memory');
check('a byte over the limit: its address', mem({ contentLength: MEMORY_MAX_BYTES + 1 }), 'stream');
check('a 300 MB hi-res file: its address', mem({ contentLength: 300e6 }), 'stream');
check('no length said: memory, counted as it comes', mem({ contentLength: null }), 'memory');
check('a transcode: its address (its length is an estimate)', mem({ raw: false }), 'stream');
check('a refused download: its address, for the element to fail on', mem({ ok: false }), 'stream');
check('not audio - an error page: its address', mem({ contentType: 'text/html' }), 'stream');
check('octet-stream: its address', mem({ contentType: 'application/octet-stream' }), 'stream');
check('no type at all: its address', mem({ contentType: null }), 'stream');
check('Ogg: memory', mem({ contentType: 'application/ogg' }), 'memory');
check('a type with parameters, in capitals: memory', mem({ contentType: 'Audio/MPEG; charset=binary' }), 'memory');
check('a smaller limit is honoured', mem({ contentLength: 2000, max: 1000 }), 'stream');
check('counting: not past the limit yet', overMemoryMax(MEMORY_MAX_BYTES), false);
check('counting: past it', overMemoryMax(MEMORY_MAX_BYTES + 1), true);
check('the limit holds a ten-minute CD-quality FLAC', MEMORY_MAX_BYTES > 10 * 6.5e6, true);

/* ========================================================================== */
console.log('\nwhich element\'s events count');

check('everything from the element playing', ['play', 'pause', 'playing', 'timeupdate', 'ended', 'error', 'durationchange']
  .every((name) => routeEvent(name, true) === 'player'), true);
check('an error from the standby: its own bookkeeping', routeEvent('error', false), 'standby');
for (const name of ['play', 'pause', 'playing', 'timeupdate', 'ended', 'durationchange', 'seeking', 'seeked',
                    'waiting', 'canplay', 'loadedmetadata']) {
  check(`the standby's ${name}: nobody's`, routeEvent(name, false), 'ignore');
}
check('whether an AirPlay device is on the network, from the element playing: the player\'s',
  routeEvent('webkitplaybacktargetavailabilitychanged', true), 'player');
//? WebKit keeps the answer per element, and the standby - made after the page began watching for
//? devices - is never told it: its 'not-available' hid the button as the switch went on
check('...from the standby: nobody\'s (its answer may be stale)', routeEvent('webkitplaybacktargetavailabilitychanged', false), 'ignore');

/* ========================================================================== */
console.log('\nwhich element is playing');

check('the first element to start with, and a one-element change keeps it', activeAfter(0, 'same element'), 0);
check('a handover moves to the other', activeAfter(0, 'handover'), 1);
check('and the next handover back again - two elements, never a third', activeAfter(activeAfter(0, 'handover'), 'handover'), 0);
check('a refused handover goes back to the one that was playing', activeAfter(activeAfter(0, 'handover'), 'refused'), 0);
check('the switch off keeps whichever is playing', activeAfter(1, 'switch off'), 1);
{
  //? a walk: on, three songs end with handovers, one refused, then the switch off mid-album
  let active = 0;
  const seen = [];
  for (const event of ['handover', 'handover', 'handover', 'refused', 'same element', 'switch off', 'same element']) {
    active = activeAfter(active, event);
    seen.push(active);
  }
  check('a walk through an album', seen, [1, 0, 1, 0, 0, 0, 0]);
}

/* ========================================================================== */
console.log('\na song that fails from memory');

const failure = (fields) => afterPlaybackFailure({
  queue: at(1), code: MEDIA_ERR_DECODE, intendsToPlay: true, retried: false, fromMemory: true, ...fields,
});

//? a decode error would otherwise skip the song straight away, when Navidrome's copy might play
check('a decode error from memory: ask Navidrome at once, not skip', failure({}), { kind: 'stream' });
check('a load error from memory: ask Navidrome at once, not wait', failure({ code: MEDIA_ERR_SRC_NOT_SUPPORTED }), { kind: 'stream' });
check('from memory after a retry already: still Navidrome - the retry is not used up', failure({ retried: true }), { kind: 'stream' });
check('from memory, nobody meaning it to play: stop, as always', failure({ intendsToPlay: false }), { kind: 'stop' });
check('from memory, aborted: stop, as always', failure({ code: MEDIA_ERR_ABORTED }), { kind: 'stop' });
check('not from memory: exactly afterFailure - a load error is retried', failure({ fromMemory: false, code: MEDIA_ERR_NETWORK }), { kind: 'retry' });
check('not from memory: exactly afterFailure - a decode error skips', failure({ fromMemory: false }), { kind: 'skip', index: 2 });
check('not from memory, last song: exactly afterFailure - stop', failure({ fromMemory: false, queue: at(3) }), { kind: 'stop' });

/* ========================================================================== */
console.log('\nthe readout');

const handed = { kind: 'handover', source: 'memory' };
const off = { kind: 'same element', reason: 'off' };
const reading = (how, ms, readyState = null, failed = false) => gapReading({ ...startChange(0, how, readyState), failed }, ms);
check('a gap is whole milliseconds', gapReading(startChange(1000.2, handed, 4), 1038.7).ms, 39);
check('a clock that went backwards is no gap, not a negative one', gapReading(startChange(1000, handed, 4), 990).ms, 0);
check('handed over from memory', describeHow(reading(handed, 30, 4)), 'handed over, from memory');
//? HAVE_FUTURE_DATA (3) is ready to play; only below it had the element to load - which is
//? what says iOS threw away what the standby buffered
check('readyState 4: ready', describeHow(reading(handed, 30, 4)), 'handed over, from memory');
check('readyState 3: ready, not "had to load"', describeHow(reading(handed, 30, 3)), 'handed over, from memory');
check('readyState 2: had to load', describeHow(reading(handed, 30, 2)), 'handed over, from memory, had to load');
check('readyState 1: had to load', describeHow(reading({ kind: 'handover', source: 'stream' }, 900, 1)), 'handed over, streamed, had to load');
check('readyState 0: had to load', describeHow(reading({ kind: 'handover', source: 'stream' }, 900, 0)), 'handed over, streamed, had to load');
check('no readyState on a handover: not "had to load"', describeHow(reading(handed, 30, null)), 'handed over, from memory');
check('its download unfinished: streamed, and no readyState to judge',
  describeHow(reading({ kind: 'handover', source: 'unfinished' }, 70, null)), 'handed over, streamed (download unfinished)');
check('the switch off', describeHow(reading(off, 900)), 'one element');
check('a fallback says why', describeHow(reading({ kind: 'same element', reason: 'nothing ready' }, 900)), 'one element (nothing ready)');
check('a refusal says so', describeHow(reading({ kind: 'same element', reason: 'refused' }, 900)), 'one element (refused)');
check('a handover whose song failed before playing says so', describeHow(reading(handed, 1600, 4, true)), 'handed over, from memory, failed before playing');
check('so does the one-element way', describeHow(reading(off, 1600, null, true)), 'one element, failed before playing');
{
  let readings = [];
  for (const ms of [900, 950, 40, 35, 30, 28]) readings = withReading(readings, reading(handed, ms, 4));
  check(`only the last ${GAPS_KEPT} are kept, newest first`, readings.map((r) => r.ms), [28, 30, 35, 40, 950]);
  check('the line', describeGaps(readings), 'Last song change 28 ms, handed over, from memory · before: 30, 35, 40, 950 ms');
}
check('before any change', describeGaps([]), 'No song change timed yet');
check('one change, nothing before it', describeGaps([reading(off, 812)]), 'Last song change 812 ms, one element');
//? inside the second after 'ended' WebKit counts anything done to an element as a tap, which marks
//? it as the one last touched - and the lock screen prefers the element last touched
check('the standby is got ready well outside the second after a song ends', PRELOAD_DELAY_MS > 1500, true);

/* ========================================================================== */
console.log('\nwhen a song change ends: the incoming clock running');

const update = (position, at, fields = {}) => ({ position, at, playbackRate: 1, seeked: false, ...fields });
{
  //? WebKit sends 'playing' from inside play(): the clock is what says there is sound
  const change = startChange(1000, handed, 4);
  const still = clockStep(change, update(0, 1010));
  check('the clock not moved yet: still waiting', still.kind, 'wait');
  check('...and nothing about the change is altered', still.change, change);
  const moved = clockStep(change, update(0.25, 1260));
  check('moved: a reading', moved.kind, 'reading');
  //? timeupdate comes every ~250ms (further apart when locked): the clock ran 250ms of it
  check('back-dated by how far the clock ran, not the 250ms between updates', moved.reading.ms, 10);
  check('back-dated at the playback rate', clockStep(change, update(1, 1260, { playbackRate: 4 })).reading.ms, 10);
  check('a rate of 0 counts as 1, never infinity', clockStep(change, update(0.25, 1260, { playbackRate: 0 })).reading.ms, 10);
  check('the reading keeps how the change was made', moved.reading.how, handed);
  //? a locked phone: the first timeupdate a second after the sound began still dates it right
  check('a late update dates it just as well', clockStep(change, update(1.05, 2100)).reading.ms, 50);
}
{
  //? the same rule the one-element way: its clock starts at 0 on the new source
  const change = startChange(5000, off, null);
  check('one element: waiting while it loads', clockStep(change, update(0, 5040)).kind, 'wait');
  check('one element: timed the same way', clockStep(change, update(0.2, 5260)).reading.ms, 60);
}
{
  //? a failed song asked for again picks up where it stopped: the seek there is not the clock
  const change = { ...startChange(0, handed, 4), failed: true };
  const sought = clockStep(change, update(12, 1500, { seeked: true }));
  check('a seek: waits again, from where it landed', [sought.kind, sought.change.from], ['wait', 12]);
  check('still not moved from there: waiting', clockStep(sought.change, update(12, 1600)).kind, 'wait');
  const after = clockStep(sought.change, update(12.1, 1700));
  check('moved from there: timed to when it started again', after.reading.ms, 1600);
  check('...and says it failed first', after.reading.failed, true);
}
{
  //? the music stopped and was started again much later: not a gap
  const change = startChange(0, off, null);
  check(`past ${CHANGE_MAX_MS / 1000}s: dropped`, clockStep(change, update(0.2, CHANGE_MAX_MS + 1)).kind, 'stale');
  check('dropped even with the clock not moved', clockStep(change, update(0, CHANGE_MAX_MS + 1)).kind, 'stale');
  check('at the bound: still timed', clockStep(change, update(0.2, CHANGE_MAX_MS)).kind, 'reading');
  check('a minute of silence is never a reading', clockStep(change, update(0.3, 61_000)).kind, 'stale');
}
check('a clock starting from somewhere else still counts from there', clockStep(startChange(0, handed, 4, 3), update(3.1, 400)).reading.ms, 300);

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
