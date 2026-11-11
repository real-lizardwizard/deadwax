/**
 * The iPhone app's screens decide as this app's do (notes/ios.md, Phase 1): the sign-in screen and Sign out, the
 * album page's "In your library", disc headings, times, meta line and footer, the queue menu, the mini player, Now
 * Playing's byline, clocks and scrubber, and what the player does with a song that won't play.
 *
 * The phone's Swift ports (ios/DeadwaxKit/Sources/DeadwaxCore: SignInRules, Whose, DiscTitles, Format, Scrub,
 * PlayerWords, QueuePick) are held by their tests to vectors in ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/screens/,
 * which ios/scripts/export-screen-vectors.cjs writes from what this app's own TypeScript answers - lib/signIn.ts,
 * lib/whose.ts, lib/discTitles.ts, lib/format.ts, lib/scrub.ts, lib/titles.ts, lib/playQueue.ts, and the components
 * app/SignIn.tsx, app/SignOutRow.tsx, app/QueueMenu.tsx and player/MiniPlayer.tsx driven as they are, with the lines
 * that live in AlbumPage.tsx, NowPlaying.tsx and signInGate.tsx read out of them and evaluated as written. This runs
 * that script with --check: every vector made again from the TypeScript as it is today and compared byte for byte
 * with the committed files - the sources' sha256 included, so even a change of words fails here. A web rule changed
 * fails here until the vectors are written again, and then the phone's Swift tests fail until the change is ported,
 * rather than the phone and the web quietly saying different things.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosscreens.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-screen-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  the screens' vectors are not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
