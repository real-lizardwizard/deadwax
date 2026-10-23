/**
 * The loading indicator: a sweeping bar.
 *
 * Still deliberately not a spinning arc — a rotating circle would read as borrowed from
 * somewhere else. A horizontal sweep suits an interface built out of rows and tables.
 *
 * It used to be ░▒▓ block glyphs, on the reasoning that they matched the filter headings.
 * Those headings are plain words now, so that reasoning expired; the animation is also
 * cheaper, because the old one swapped the `content` property twelve times a second and
 * each swap was a layout plus a paint.
 *
 * The animation lived in the main page's main.css (`.loading-blocks` / `.loading-panel`); since that
 * page retired (2.0.0-player.66) the app's sheets draw it where it shows (app-desktop.css's Edit
 * panel). The class names are unchanged.
 */

/** Inline, next to a label. Use when there's already something on screen. */
export function Loading({ label }: { label?: string }) {
  return (
    <span class="loading-blocks text default-muted" role="status" aria-live="polite">
      {label ? <span>{label}</span> : null}
    </span>
  )
}

/**
 * Centred in an otherwise empty panel.
 *
 * Takes a label because "loading" on its own tells you nothing about why you're waiting -
 * a first library scan reads tags off every file and can genuinely take a while, and that's
 * much easier to sit through when the screen says so.
 */
export function LoadingPanel({ label }: { label: string }) {
  return (
    <div class="loading-panel" role="status" aria-live="polite">
      <span>{label}</span>
    </div>
  )
}
