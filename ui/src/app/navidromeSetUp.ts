/**
 * "Set up Navidrome" (2.0.0-player.47): the Navidrome gate's way to the app's own Server settings, opened
 * at Connections - on every frame, a phone's included, so a first run from a phone can set Navidrome up
 * in the app. A module, as searchBox.ts is: the gate (NeedsNavidrome.tsx) is drawn by Home,
 * Search, the Library and the album and artist pages, and App - which is what opens pages - says what the
 * button does, so none of them is handed it. Until App has said, the button does nothing.
 */

let handler: (() => void) | null = null

/** What "Set up Navidrome" does - App's, from its first render. Returns the off switch. */
export function setUpNavidromeBy(next: () => void): () => void {
  handler = next
  return () => {
    if (handler === next) handler = null
  }
}

/** The gate's button: Server settings, at Connections. */
export function setUpNavidrome(): void {
  handler?.()
}
