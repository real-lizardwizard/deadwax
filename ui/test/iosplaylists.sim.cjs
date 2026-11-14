/**
 * The iPhone app's playlist rules are the web's (Phase 4, notes/ios-specs/phase4-library.md 7):
 * ios/scripts/export-playlist-vectors.cjs runs lib/playlists.ts and lib/playedAlbums.ts on every case it holds - the
 * words and limits, each playlist's group and lines, the groups, the counts and lengths, the hidden line, the album
 * stubs a playlist's songs are remembered under and what is held over them, the store of albums played from - and
 * compares what they answer with the fixture DeadwaxCore's PlaylistVectorTests replay
 * (ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/playlists/playlist-vectors.json). A rule changed here and not there -
 * or the fixture edited by hand - fails, saying how to bring them together: run the script, and make the Swift say the
 * same.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosplaylists.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')

let failures = 0
try {
  const said = execFileSync(process.execPath, [path.join(REPO, 'ios/scripts/export-playlist-vectors.cjs'), '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  console.log(`  FAIL  ${String(error.stderr || error.message).trim()}`)
}

console.log(failures ? `\n${failures} failed` : '\nall passed')
process.exit(failures ? 1 : 0)
