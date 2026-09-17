import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { applyArtistImages, fetchArtist, previewArtistImages } from '../api/library'
import type { ArtistImageCandidate, ArtistImagesPreview, ArtistSummary } from '../api/types'
import { artistArtUrl, formatSize } from '../lib/format'
import type { AlbumGroup } from '../lib/groupAlbums'
import { Loading } from './Loading'
import { ArtistIcon, CoverGrid } from './LibraryParts'

/**
 * An artist page: who they are, what you have of them, and what they look like.
 *
 * Two halves, loaded separately on purpose. The library half is derived from the scan already
 * in memory and draws at once. The MusicBrainz half needs a stranger's server, three of them in
 * fact - MusicBrainz for the facts, TheAudioDB and Wikimedia for the pictures - any of which
 * can be slow or down, and none of which should be asked anything while you are still arrowing
 * down the tree. Hence the debounce: settle on an artist for a moment and it fills in.
 *
 * **MusicBrainz hosts no artist images at all** - see src/artists.py. What arrives here is a
 * photograph from Wikimedia Commons, and, when a TheAudioDB key is set, the banner, logo,
 * background and wide shot that an artist page is actually made of.
 */

//? long enough that walking the tree with the arrow keys asks nobody anything, short enough
//? that settling on an artist feels like it just knows. The tag editor's preview uses the same.
const LOOKUP_DELAY_MS = 400

//? Dance Gavin Dance has nineteen past and present members, which is a screen of names between
//? the facts and the albums. The current line-up sorts first, so this shows that and says how
//? many came before.
const MEMBERS_SHOWN = 10

export function ArtistDetails(
  { artist, groups, onSelect }:
  {
    artist: string
    groups: readonly AlbumGroup[]
    onSelect: (id: string) => void
  },
) {
  const [summary, setSummary] = useState<ArtistSummary | null>(null)
  const [lookup, setLookup] = useState<ArtistImagesPreview | null>(null)
  const [looking, setLooking] = useState(false)
  const [picking, setPicking] = useState(false)
  //? the art URLs name a KIND, not a file, so replacing artist.jpg leaves the address unchanged
  //? and the five-minute cache would go on serving the old one
  const [version, setVersion] = useState(0)

  //? what the library knows, which needs nobody's permission
  useEffect(() => {
    let live = true
    setSummary(null)
    setLookup(null)
    fetchArtist(artist).then(
      (found) => { if (live) setSummary(found) },
      () => { if (live) setSummary(null) },
    )
    return () => { live = false }
  }, [artist])

  //? and what the world knows, once you have stopped moving
  useEffect(() => {
    let live = true
    const timer = window.setTimeout(() => {
      setLooking(true)
      previewArtistImages(artist).then(
        (found) => { if (live) { setLookup(found); setLooking(false) } },
        () => { if (live) { setLookup(null); setLooking(false) } },
      )
    }, LOOKUP_DELAY_MS)

    return () => { live = false; window.clearTimeout(timer) }
  }, [artist])

  const facts = lookup?.facts ?? null
  const art = summary?.art ?? {}
  const path = summary?.path ?? null

  const refresh = useCallback(async () => {
    const [found, again] = await Promise.all([
      fetchArtist(artist),
      previewArtistImages(artist, { artistMbid: lookup?.mbid ?? null }),
    ])
    setSummary(found)
    setLookup(again)
    setVersion((n) => n + 1)
  }, [artist, lookup?.mbid])

  //? oldest first: an artist page is read as a career, not as an alphabet
  const byYear = useMemo(
    () => [...groups].sort((a, b) => (a.year || '9999').localeCompare(b.year || '9999')),
    [groups],
  )

  const hero = path && art['fanart'] ? artistArtUrl(path, 'fanart', version) : null
  const square = path && art['thumb'] ? artistArtUrl(path, 'thumb', version) : null
  const logo = path && art['logo'] ? artistArtUrl(path, 'logo', version) : null

  return (
    <section class="details-section artist-page">
      <div
        class={`artist-hero${hero ? ' has-background' : ''}`}
        style={hero ? `background-image:url(${JSON.stringify(hero)})` : undefined}
      >
        <div class="artist-hero-portrait">
          {square
            ? <img src={square} alt={artist} />
            : <div class="details-artist-badge" aria-hidden="true"><ArtistIcon /></div>}
        </div>

        <div class="artist-hero-text">
          {logo
            ? <img class="artist-hero-logo" src={logo} alt={artist} />
            : <h2 class="details-title">{artist}</h2>}

          <div class="details-facts text default-muted">{describe(facts, summary)}</div>

          {facts && facts.genres.length > 0 && (
            <div class="artist-genres">
              {facts.genres.slice(0, 6).map((genre) => (
                <span key={genre} class="artist-genre">{genre}</span>
              ))}
            </div>
          )}
        </div>

        <div class="artist-hero-actions">
          <button
            type="button"
            class="win-button"
            disabled={!path || looking}
            title={path
              ? 'Pictures of this artist, written into their folder where other apps read them'
              : summary?.folder_problem ?? 'this artist has no folder of their own'}
            onClick={() => setPicking(true)}
          >
            Artist images…
          </button>
        </div>
      </div>

      {looking && !facts && <Loading label="Looking this artist up" />}

      {lookup && !facts && !looking && lookup.problems.length > 0 && (
        <p class="text white-tertiary artist-note">{lookup.problems[0]}</p>
      )}

      <div class="artist-columns">
        <div class="artist-column">
          <h3 class="details-subheading">In your library</h3>
          <dl class="property-grid">
            <dt>Albums</dt><dd>{summary?.album_count ?? groups.length}</dd>
            <dt>Tracks</dt><dd>{summary?.track_count ?? '·'}</dd>
            <dt>Size</dt><dd>{summary ? formatSize(summary.total_size) : '·'}</dd>
            {summary?.first_year && (
              <>
                <dt>Years</dt>
                <dd>{summary.first_year === summary.last_year
                  ? summary.first_year
                  : `${summary.first_year}–${summary.last_year}`}</dd>
              </>
            )}
            <dt>Folder</dt>
            <dd class="artist-folder">{path ?? <span class="text white-tertiary">{summary?.folder_problem ?? '·'}</span>}</dd>
          </dl>
        </div>

        {facts && (
          <div class="artist-column">
            <h3 class="details-subheading">MusicBrainz</h3>
            <dl class="property-grid">
              {facts.type && <><dt>Type</dt><dd>{facts.type}</dd></>}
              {facts.area && <><dt>From</dt><dd>{facts.begin_area || facts.area}</dd></>}
              {facts.began && (
                <>
                  <dt>{facts.type === 'Person' ? 'Born' : 'Active'}</dt>
                  <dd>{facts.began}{facts.ended ? `–${facts.ended_on || 'ended'}` : '–'}</dd>
                </>
              )}
              {facts.aliases.length > 0 && <><dt>Also</dt><dd>{facts.aliases.join(', ')}</dd></>}
            </dl>

            {facts.links.length > 0 && (
              <div class="artist-links">
                {facts.links.slice(0, 8).map((link) => (
                  <a key={link.url} href={link.url} target="_blank" rel="noreferrer noopener">
                    {link.label}
                  </a>
                ))}
              </div>
            )}
          </div>
        )}
      </div>

      {facts && facts.members.length > 0 && (
        <>
          <h3 class="details-subheading">Line-up</h3>
          <ul class="artist-members">
            {facts.members.slice(0, MEMBERS_SHOWN).map((member) => (
              <li key={`${member.mbid ?? member.name}`} class={member.current ? '' : 'is-past'}>
                <span class="artist-member-name">{member.name}</span>
                {member.roles.length > 0 && (
                  <span class="text white-tertiary"> {member.roles.slice(0, 3).join(', ')}</span>
                )}
                <span class="text default-muted">
                  {' '}{member.began || '?'}{member.current ? '–' : `–${member.ended || ''}`}
                </span>
              </li>
            ))}
            {facts.members.length > MEMBERS_SHOWN && (
              <li class="text white-tertiary">
                +{facts.members.length - MEMBERS_SHOWN} earlier members
              </li>
            )}
          </ul>
        </>
      )}

      <h3 class="details-subheading">Albums</h3>
      <CoverGrid groups={byYear} showArtist={false} onSelect={onSelect} />

      {picking && path && lookup && (
        <ArtistImagePicker
          artist={artist}
          preview={lookup}
          version={version}
          onClose={() => setPicking(false)}
          onSaved={refresh}
        />
      )}
    </section>
  )
}


/**
 * Choosing which picture goes where.
 *
 * Every candidate the sources offered, grouped by what it would be written as. Picking is the
 * point: TheAudioDB often has four backgrounds, and which one belongs at the top of a page is
 * not something a rule can decide.
 */
function ArtistImagePicker(
  { artist, preview, version, onClose, onSaved }:
  {
    artist: string
    preview: ArtistImagesPreview
    version: number
    onClose: () => void
    onSaved: () => Promise<void>
  },
) {
  const [chosen, setChosen] = useState<Record<string, string>>(
    () => Object.fromEntries(Object.entries(preview.best).map(([kind, c]) => [kind, c.url])),
  )
  const [replace, setReplace] = useState(false)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState<string | null>(null)
  const dialog = useRef<HTMLDivElement>(null)

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.stopPropagation()
      onClose()
    }
    window.addEventListener('keydown', onKeyDown, true)
    return () => window.removeEventListener('keydown', onKeyDown, true)
  }, [onClose])

  const byKind = useMemo(() => {
    const grouped: Record<string, ArtistImageCandidate[]> = {}
    for (const candidate of preview.candidates) {
      (grouped[candidate.kind] ??= []).push(candidate)
    }
    return grouped
  }, [preview.candidates])

  const save = async () => {
    setSaving(true)
    setSaved(null)
    try {
      const result = await applyArtistImages(artist, chosen, {
        artistMbid: preview.mbid, replace,
      })
      const written = result.results.written
      setSaved(written.length
        ? `Saved ${written.join(', ')}.`
        : (result.results.problems[0] ?? 'Nothing needed writing.'))
      await onSaved()
    } catch (error) {
      setSaved(error instanceof Error ? error.message : 'That could not be saved.')
    } finally {
      setSaving(false)
    }
  }

  return (
    <div id="artist-images" role="dialog" aria-modal="true" aria-label="Artist images" onClick={onClose}>
      <div class="artist-images-frame" ref={dialog} onClick={(event) => event.stopPropagation()}>
        <div class="window-titlebar">
          <span class="window-title">Artist images · {artist}</span>
          <button type="button" class="window-close" title="Close (Esc)" onClick={onClose}>✕</button>
        </div>

        <div class="artist-images-body">
          {!preview.has_key && (
            <p class="text white-tertiary artist-note">
              Banners, logos and backgrounds come from TheAudioDB. Without a key in the settings
              tab there is only whatever Wikimedia Commons has, which is usually one photograph.
            </p>
          )}

          {preview.kinds.map(({ kind, label }) => {
            const options = byKind[kind] ?? []
            const existing = preview.art?.[kind]

            return (
              <div key={kind} class="artist-images-row">
                <div class="artist-images-label">
                  <strong>{label}</strong>
                  <span class="text default-muted">
                    {existing ? ` ${existing} on disk` : options.length ? '' : ' none found'}
                  </span>
                </div>

                <div class="artist-images-options">
                  {options.map((candidate) => (
                    <button
                      key={candidate.url}
                      type="button"
                      class={`artist-images-option${chosen[kind] === candidate.url ? ' is-chosen' : ''}`}
                      title={`${candidate.label} — ${candidate.source}`}
                      onClick={() => setChosen((current) => (
                        current[kind] === candidate.url
                          //? clicking the chosen one again means "don't write this kind"
                          ? Object.fromEntries(Object.entries(current).filter(([k]) => k !== kind))
                          : { ...current, [kind]: candidate.url }
                      ))}
                    >
                      <img src={candidate.preview} alt={candidate.label} loading="lazy" />
                      <span class="text default-muted">{candidate.source}</span>
                    </button>
                  ))}
                  {options.length === 0 && existing && (
                    <img
                      class="artist-images-option is-existing"
                      src={artistArtUrl(preview.path ?? '', kind, version)}
                      alt={label}
                    />
                  )}
                </div>
              </div>
            )
          })}
        </div>

        <div class="artist-images-footer">
          <label class="settings-check">
            <input
              type="checkbox"
              checked={replace}
              onChange={(event) => setReplace((event.target as HTMLInputElement).checked)}
            />
            <span>Replace pictures that are already there</span>
          </label>

          {saved && <span class="text white-tertiary">{saved}</span>}

          <button
            type="button"
            class="win-button is-default"
            disabled={saving || Object.keys(chosen).length === 0}
            onClick={save}
          >
            {saving ? <Loading label="Saving" /> : 'Save'}
          </button>
          <button type="button" class="win-button" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  )
}

/** The one line under the name: what they are, where from, and how long they have been at it. */
function describe(facts: ArtistImagesPreview['facts'], summary: ArtistSummary | null): string {
  const parts: string[] = []

  if (facts?.type) parts.push(facts.type)
  if (facts?.begin_area || facts?.area) parts.push(facts.begin_area || facts.area)
  if (facts?.began) parts.push(facts.ended ? `${facts.began}–${facts.ended_on || ''}` : `since ${facts.began}`)
  if (summary) {
    parts.push(`${summary.album_count} album${summary.album_count === 1 ? '' : 's'}`)
    parts.push(`${summary.track_count} tracks`)
  }

  return parts.filter(Boolean).join(' · ')
}
