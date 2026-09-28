/**
 * The now-playing scrubber: which time a point on the bar is, what a finger and the keys do, which
 * position the bar shows while a seek is on its way, and what the readout says about where the
 * last seek landed.
 *
 * A script for the same reason as the other sims: there is no JS test runner here. What it pins is
 * the difference between "it seeks where I put it" and not - a release that seeks to where the
 * finger was a move ago, a second finger moving the seek, a cancelled touch that seeks anyway or
 * leaves the bar stuck, a drag carried over to the next song, the thumb going back to the old time
 * while a seek is on its way (or held there for good when one never lands), arrow keys stepping
 * from the old time instead of the one just asked for - and a readout that calls a seek landed
 * when its song's end says otherwise, blames one the listener didn't make, fills in "the player
 * said" from a seek that replaced it, or says "seeking…" for good about one that never landed.
 *
 * Run it with:  node ui/test/scrub.sim.cjs
 */

const { execFileSync } = require('child_process');
const fs = require('fs'), os = require('os'), path = require('path');

const UI = path.resolve(__dirname, '..');
const OUT = fs.mkdtempSync(path.join(os.tmpdir(), 'deadwax-scrub-'));

execFileSync(path.join(UI, 'node_modules/.bin/tsc'), [
  'src/lib/scrub.ts', '--rootDir', 'src', '--outDir', OUT,
  '--module', 'commonjs', '--target', 'es2022', '--skipLibCheck', '--moduleResolution', 'node',
], { cwd: UI, stdio: 'inherit' });

const {
  clock, timeAt, keyTarget, dragStart, dragMove, dragEnd, dragFor, shownTime, reportedPosition,
  seekStep, describeSeek, KEY_STEP_S, PAGE_STEP_S, PENDING_MAX_MS, END_SLACK_S, LANDED_WITHIN_S,
} = require(path.join(OUT, 'lib/scrub.js'));

let failures = 0;
function check(label, actual, expected) {
  const ok = JSON.stringify(actual) === JSON.stringify(expected);
  if (!ok) failures++;
  console.log(`  ${ok ? 'PASS' : 'FAIL'}  ${label}: ${JSON.stringify(actual)}` +
              (ok ? '' : `  (expected ${JSON.stringify(expected)})`));
}

/* ========================================================================== */
console.log('\na point on the bar');

check('the left end is the start', timeAt(100, 100, 400, 300), 0);
check('the right end is the end', timeAt(500, 100, 400, 300), 300);
check('the middle is half way', timeAt(300, 100, 400, 300), 150);
check('60% across', timeAt(340, 100, 400, 300), 180);
check('a finger past the left end is at the start', timeAt(40, 100, 400, 300), 0);
check('a finger past the right end is at the end', timeAt(900, 100, 400, 300), 300);
check('no length yet: nothing to seek to', timeAt(300, 100, 400, 0), 0);
check('a bar with no width (not laid out): 0, not NaN', timeAt(300, 100, 0, 300), 0);

/* ========================================================================== */
console.log('\nthe keys');

check('right arrow: forward a step', keyTarget('ArrowRight', 60, 300), 60 + KEY_STEP_S);
check('up arrow (VoiceOver swipe up): forward a step', keyTarget('ArrowUp', 60, 300), 60 + KEY_STEP_S);
check('left arrow: back a step', keyTarget('ArrowLeft', 60, 300), 60 - KEY_STEP_S);
check('down arrow: back a step', keyTarget('ArrowDown', 60, 300), 60 - KEY_STEP_S);
check('page up: forward a page', keyTarget('PageUp', 60, 300), 60 + PAGE_STEP_S);
check('page down: back a page', keyTarget('PageDown', 60, 300), 60 - PAGE_STEP_S);
check('home: the start', keyTarget('Home', 60, 300), 0);
check('end: the end', keyTarget('End', 60, 300), 300);
check('back from 2 s stops at the start', keyTarget('ArrowLeft', 2, 300), 0);
check('forward from 298 s stops at the end', keyTarget('ArrowRight', 298, 300), 300);
check('a key that is not the bar\'s: null, so the page keeps it', keyTarget('Tab', 60, 300), null);
check('space is not a seek', keyTarget(' ', 60, 300), null);
check('no length yet: no key seeks', keyTarget('ArrowRight', 0, 0), null);
//? the player keeps showing a seek's target until it lands, and the bar steps from what it shows:
//? three presses in a row go 15 s, not 5 s three times from the same place
let at = 60;
for (let i = 0; i < 3; i++) at = keyTarget('ArrowRight', shownTime(null, reportedPosition({ target: at, since: 0 }, 60, 10), 300), 300);
check('three quick presses step from each other\'s targets', at, 60 + 3 * KEY_STEP_S);

/* ========================================================================== */
console.log('\na finger on the bar');

let drag = dragStart(7, 'song-a', 40);
check('put down: it is where the finger is', drag, { pointer: 7, track: 'song-a', time: 40 });
check('the bar shows the finger, not the song', shownTime(drag, 12, 300), 40);
drag = dragMove(drag, 7, 90);
check('moved: it follows', drag.time, 90);
check('a second finger moving changes nothing', dragMove(drag, 8, 250), drag);
check('a move to where it already is is the same drag (no render)', dragMove(drag, 7, 90) === drag, true);
check('no drag: a move is nothing', dragMove(null, 7, 90), null);
check('a second finger lifted changes nothing', dragEnd(drag, 8, 'up'), { drag, seek: null });
check('let go: seeks to where the LAST move put it', dragEnd(drag, 7, 'up'), { drag: null, seek: 90 });
check('cancelled (the system took the touch): seeks nowhere, and lets go', dragEnd(drag, 7, 'cancel'), { drag: null, seek: null });
check('after it is gone, the lost capture that follows an up does nothing', dragEnd(null, 7, 'cancel'), { drag: null, seek: null });
check('a tap is a drag that never moved: seeks where it landed', dragEnd(dragStart(3, 'song-a', 180), 3, 'up'), { drag: null, seek: 180 });
check('the song changed under the finger: the drag is let go of', dragFor(drag, 'song-b'), null);
check('same song: the drag stays', dragFor(drag, 'song-a'), drag);
check('let go, the bar shows the song\'s position again', shownTime(null, 12, 300), 12);
check('the bar never shows past the end', shownTime(dragStart(1, 'a', 400), 12, 300), 300);
check('nor before the start', shownTime(null, -3, 300), 0);
check('with no length yet, the position as it is', shownTime(null, 5, 0), 5);

/* ========================================================================== */
console.log('\nwhile a seek is on its way');

const pending = { target: 180, since: 1000 };
check('the target, not where the song was', reportedPosition(pending, 25, 1200), 180);
check('an update from before the seek lands can\'t move it', reportedPosition(pending, 24.8, 3000), 180);
check('no seek on its way: the song\'s position', reportedPosition(null, 25, 1200), 25);
check('one that never landed lets go after a while', reportedPosition(pending, 25, 1000 + PENDING_MAX_MS), 25);
check('...and not before', reportedPosition(pending, 25, 1000 + PENDING_MAX_MS - 1), 180);

/* ========================================================================== */
console.log('\nthe readout: where the last seek landed');

const asked = (at = 130, length = 300) => seekStep(null, { kind: 'asked', asked: at, length, track: 's1' });
check('nothing yet', describeSeek(null), 'No seek yet');
let r = asked();
check('asked, on its way', describeSeek(r), 'Last seek: asked 2:10, seeking…');
r = seekStep(r, { kind: 'seeked', position: 130 });
check('landed, by the element\'s clock', describeSeek(r), 'Last seek: asked 2:10, the player said 2:10');
check('a second seeked (an older seek\'s) doesn\'t overwrite what it said', seekStep(r, { kind: 'seeked', position: 90 }).said, 130);
check('an update before the end changes nothing', seekStep(r, { kind: 'clock', position: 200, at: 5000 }) === r, true);
check('nothing asked yet: events are nothing', seekStep(null, { kind: 'ended', position: 300, at: 1, rate: 1 }), null);

//? a browser that lands where asked (Chromium, measured): the clock reaches the end, 'ended' follows
let fine = seekStep(r, { kind: 'clock', position: 299.8, at: 100000 });
check('the clock reaching the end is noted', fine.clockEnd, { at: 100000, position: 299.8 });
check('...once', seekStep(fine, { kind: 'clock', position: 300, at: 100200 }) === fine, true);
fine = seekStep(fine, { kind: 'ended', position: 300, at: 100210, rate: 1 });
check('ended with its clock: landed where asked', fine.off, 0);
check('says so', describeSeek(fine), 'Last seek: asked 2:10, the player said 2:10 · the song ended on time, so it landed there');
check('judged once', fine.judging, false);

//? Safari landing LATER than asked (the audio ahead of its clock): the audio runs out first, and
//? WebKit takes the clock then for the song's length - 'ended' comes with the clock 7 s short
const late = seekStep(r, { kind: 'ended', position: 293, at: 50000, rate: 1 });
check('ran out 7 s before the clock: landed 7 s later', late.off, 7);
check('says where it really landed', describeSeek(late),
  'Last seek: asked 2:10, the player said 2:10 · the song ran out 7 s before its clock did, so it really landed at about 2:17');

//? Safari landing EARLIER (the audio behind): WebKit holds its clock at the length while the song
//? plays on, and 'ended' comes when the audio runs out, measured on the wall clock
let early = seekStep(r, { kind: 'clock', position: 299.8, at: 100000 });
early = seekStep(early, { kind: 'clock', position: 300, at: 103000 });
early = seekStep(early, { kind: 'ended', position: 300, at: 107200, rate: 1 });
check('played on 7 s after its clock stopped: landed 7 s earlier', early.off, -7);
check('says where it really landed', describeSeek(early),
  'Last seek: asked 2:10, the player said 2:10 · the song played on 7 s after its clock ended, so it really landed at about 2:03');
check('the measured case: asked 4:00, landed 1:35 (145 s early)', describeSeek(seekStep(seekStep(seekStep(asked(240), { kind: 'seeked', position: 240 }),
  { kind: 'clock', position: 299.9, at: 0 }), { kind: 'ended', position: 300, at: 144900, rate: 1 })).endsWith('at about 1:35'), true);
check('at double speed the song plays on twice as far', seekStep(seekStep(r, { kind: 'clock', position: 300, at: 0 }), { kind: 'ended', position: 300, at: 3500, rate: 2 }).off, -7);

check(`off by under ${LANDED_WITHIN_S} s is where asked (Navidrome's rounded length, update spacing)`,
  seekStep(r, { kind: 'ended', position: 299.2, at: 1, rate: 1 }).off, 0);
check(`the clock within ${END_SLACK_S} s of the length counts as at the end`,
  seekStep(r, { kind: 'clock', position: 300 - END_SLACK_S, at: 5 }).clockEnd !== null, true);
check('...and further back does not', seekStep(r, { kind: 'clock', position: 299, at: 5 }).clockEnd, null);

//? what stops the end speaking for the seek
const judged = (reading) => seekStep(seekStep(reading, { kind: 'clock', position: 299.9, at: 0 }), { kind: 'ended', position: 300, at: 60000, rate: 1 });
check('a pause near the end: the wall clock is no measure after it, so no judgement',
  judged(seekStep(r, { kind: 'paused' })).off, null);
check('another seek ("previous" restarting, a resume): the end is no longer about this one',
  judged(seekStep(r, { kind: 'other seek' })).off, null);
check('the song changed before its end: never judged', judged(seekStep(r, { kind: 'song change' })).off, null);
check('...and the line says only what the clock said', describeSeek(seekStep(r, { kind: 'song change' })),
  'Last seek: asked 2:10, the player said 2:10');
check('not landed yet when the song ended: nothing to judge', seekStep(asked(), { kind: 'ended', position: 300, at: 1, rate: 1 }).off, null);

//? A seek that never landed: the element answers only the newest seek, and a new song or a failure
//? aborts one on its way. A 'seeked' after that is somebody else's, and "seeking…" would be for good.
const restarted = seekStep(seekStep(asked(120), { kind: 'other seek' }), { kind: 'seeked', position: 0 });
check('"previous" during a seek to 2:00: the restart\'s 0:00 is not what the player said for it',
  restarted.said, null);
check('...it says the seek was interrupted', describeSeek(restarted), 'Last seek: asked 2:00, interrupted');
const moved = seekStep(asked(90), { kind: 'song change' });
check('the song changed before the seek landed: interrupted, not "seeking…" for good',
  describeSeek(moved), 'Last seek: asked 1:30, interrupted');
check('...and the next song\'s \'seeked\' doesn\'t fill it in', seekStep(moved, { kind: 'seeked', position: 12 }).said, null);
check('the song failed under the seek: interrupted', describeSeek(seekStep(asked(90), { kind: 'failed' })),
  'Last seek: asked 1:30, interrupted');
check('...and its end is judged no more', seekStep(r, { kind: 'failed' }).judging, false);
const pausedMidSeek = seekStep(seekStep(asked(90), { kind: 'paused' }), { kind: 'seeked', position: 90 });
check('a pause doesn\'t stop a seek on its way: its \'seeked\' still counts', pausedMidSeek.said, 90);
check('...but the end can no longer judge it', pausedMidSeek.judging, false);
check('closing a closed reading changes nothing', seekStep(moved, { kind: 'song change' }) === moved, true);
check('a new seek starts a new reading', seekStep(late, { kind: 'asked', asked: 60, length: 300, track: 's1' }).off, null);
check('a seek with no length known can\'t be judged', asked(130, 0).judging, false);

console.log('\nclock');
check('3:07', clock(187.9), '3:07');
check('nothing is 0:00', clock(NaN), '0:00');
check('never negative', clock(-4), '0:00');

console.log(failures ? `\n${failures} FAILED` : '\nall passed');
process.exit(failures ? 1 : 0);
