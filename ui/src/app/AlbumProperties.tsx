import { Fragment } from 'preact'

import { releaseUrl, type PropertyRow } from '../lib/albumProperties'

/**
 * An album page's Properties (2.0.0-player.44), at the foot of the page on both frames: what the main
 * page's details pane says of the album that the page didn't - its year against this pressing's, its
 * size, its release on musicbrainz.org and when deadwax first saw it (lib/albumProperties.ts says which,
 * from the id bridge's answer). The release opens beside the app (target="_blank" rel="noopener"):
 * followed in the page it would unload the player, the music and the queue with it. Nothing until the
 * bridge has answered - drawn below the songs, so its arriving moves nothing above it.
 */
export function AlbumProperties({ rows }: { rows: PropertyRow[] | null }) {
  if (!rows || !rows.length) return null
  return (
    <section class="app-props">
      <h2 class="app-props-title">Properties</h2>
      <dl class="app-props-list">
        {rows.map((row) => (
          <Fragment key={row.label}>
            <dt class="app-props-label">{row.label}</dt>
            <dd class={`app-props-value${row.quiet ? ' is-quiet' : ''}`}>
              {row.release ? (
                <a class="app-props-link" href={releaseUrl(row.release)} target="_blank" rel="noopener">
                  {row.text}
                </a>
              ) : (
                row.text
              )}
            </dd>
          </Fragment>
        ))}
      </dl>
    </section>
  )
}
