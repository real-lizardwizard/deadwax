/**
 * The Mac app's desktop frame is this app's (notes/ios.md, "The Mac app, slice 3: the desktop frame"): which panel a
 * window's width gives and which of Up Next, Lyrics and Info shows, the sidebar's one Library group with its Yours | All
 * switch, the groups that fold, the playlists it lists, and the frame's sizes.
 *
 * The Mac's Swift port (ios/DeadwaxKit/Sources/DeadwaxCore/MacFrame.swift and MacSidebar.swift) is held by its tests to
 * ios/DeadwaxKit/Tests/DeadwaxCoreTests/Fixtures/frame/frame-vectors.json, which ios/scripts/export-frame-vectors.cjs
 * makes by running lib/appFrame.ts, lib/appRoutes.ts, lib/playlists.ts and state/persisted.ts as they are, and reading
 * app/Sidebar.tsx's words and app-desktop.css's sizes. This runs that script with --check: every case made again from
 * the TypeScript as it is today and compared byte for byte with the committed file - each source's sha256 included, so
 * even a change of words fails here. A web rule changed fails here until the fixture is written again, and then the
 * Mac's Swift tests fail until the change is ported.
 *
 * Run it with:  TMPDIR=<writable> node ui/test/iosframe.sim.cjs
 */

const { execFileSync } = require('child_process')
const path = require('path')

const REPO = path.resolve(__dirname, '..', '..')
const SCRIPT = path.join(REPO, 'ios', 'scripts', 'export-frame-vectors.cjs')

let failures = 0
try {
  const said = execFileSync(process.execPath, [SCRIPT, '--check'], { cwd: REPO, encoding: 'utf8' })
  console.log(`  PASS  ${said.trim()}`)
} catch (error) {
  failures++
  process.stdout.write(error.stdout || '')
  process.stderr.write(error.stderr || '')
  console.log(`  FAIL  the desktop frame's fixture is not what the web's TypeScript answers today (exit ${error.status})`)
}

console.log(failures ? `\n${failures} FAILED` : '\nall passed')
process.exit(failures ? 1 : 0)
