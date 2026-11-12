/**
 * The iPhone app's lyrics rules are the web's (app 0.4, notes/app-lyrics.md 4.8): ios/scripts/export-lyrics-vectors.cjs
 * runs lib/lyricsView.ts on every case it holds - the words, the button's names and dimming, the clock, the lit line,
 * the intro, the dots, following, a line's time as VoiceOver says it, the next song's ask, the answers kept - and
 * compares what it answers with the fixture DeadwaxCore's LyricsTests replay
 * (ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/lyrics/lyrics-vectors.json). A rule changed here and not there - or
 * the fixture edited by hand - fails, saying how to bring them together: run the script, and make Lyrics.swift say
 * the same.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/ioslyrics.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')

let failures = 0
try {
  const said = execFileSync(process.execPath, [path.join(REPO, 'ios/scripts/export-lyrics-vectors.cjs'), '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  console.log(`  FAIL  ${String(error.stderr || error.message).trim()}`)
}

console.log(failures ? `\n${failures} failed` : '\nall passed')
process.exit(failures ? 1 : 0)
