import { useCallback, useEffect, useMemo, useRef, useState } from 'preact/hooks'

import * as api from '../api/download'
import type { Candidate, FindCandidatesRequest, FindCandidatesResponse } from '../api/types'
import { bridge } from '../bridge'
import {
  EDITION_TAG_COLORS, PEER_SPEED_HINT, SIGNAL_LABELS, activeSignalCount, bitrateText,
  candidateKey, measuredSpeed, noSignalMinimums, passesFilters, peerSpeedLabel, queryOverride,
  resultFormats, scoreClass, trackSummary, type CandidateFilters,
} from '../lib/candidates'
import { requestDownload } from '../lib/downloadRequests'
import { formatSize } from '../lib/format'
import { isAbort, latestOnly } from '../lib/latest'
import { readDownloadDefaults, readPreferences } from '../state/persisted'

/**
 * The Soulseek candidates window - ported from interface/scripts/main.js in v0.9.10.
 *
 * Opened by the vanilla releases grid's Find buttons through the bridge (`openCandidates`),
 * since those are still main.js's. Markup, ids and class names are the vanilla panel's exactly,
 * so main.css and resize.js (which moves this window by #candidates-header) apply unchanged.
 *
 * What the port had to keep, each learned the hard way (see CLAUDE.md):
 * - ONE search value, which only the newest search becomes (lib/latest.ts, v0.9.2) - a slow
 *   answer for the album you left must never draw under the album you went to, and each row
 *   downloads as the release IT was searched for;
 * - filters changed mid-search apply to the answer when it lands, and never redraw the last one;
 * - Re-search overrides only when the query was EDITED (lib/candidates.ts, queryOverride);
 * - the advertised speed reads "peer avg", never a bare rate.
 */

interface Search {
  /** The release, exactly as the Find button built it - also what a download is filed as. */
  release: FindCandidatesRequest
  pending: boolean
  result: FindCandidatesResponse | null
  error: string | null
}

type DownloadState = 'queueing' | 'queued' | 'failed'

export function CandidatesPanel() {
  const [open, setOpen] = useState(false)
  const [label, setLabel] = useState('—')
  const [search, setSearch] = useState<Search | null>(null)
  const [query, setQuery] = useState('')
  const [shownQuery, setShownQuery] = useState('')
  const [downloads, setDownloads] = useState<ReadonlyMap<string, DownloadState>>(() => new Map())
  const requests = useMemo(latestOnly, [])

  //? Seeded from the settings tab's preferences once, as the vanilla panel did at module scope:
  //? changing a filter here is meant to be temporary, and re-reading per search would snap the
  //? panel's own controls back under you mid-session.
  const [filters, setFilters] = useState<CandidateFilters>(() => {
    const preferences = readPreferences()
    return {
      freeSlotOnly: preferences.candidateFreeSlotOnly,
      completeOnly: preferences.candidateCompleteOnly,
      minScore: preferences.candidateMinScore,
      formats: new Set(),
      minSignals: noSignalMinimums(),
    }
  })

  const run = useCallback(async (release: FindCandidatesRequest, override: string) => {
    const request = requests.begin()
    setSearch({ release, pending: true, result: null, error: null })
    setDownloads(new Map())
    //? the format chips were the last result's formats; filtering this search by them would be
    //? filtering on a question nobody has answered yet
    setFilters((current) => (current.formats.size ? { ...current, formats: new Set() } : current))

    try {
      const result = await api.findCandidates(
        //? read per search, so a format preference changed in settings applies at once
        { ...release, query_override: override, format_preference: readDownloadDefaults().formatPreference },
        request.signal,
      )
      if (!request.current()) return
      setSearch({ release, pending: false, result, error: null })
      setQuery(result.query)
      setShownQuery(result.query)
    } catch (caught) {
      if (!request.current() || isAbort(caught)) return
      setSearch({ release, pending: false, result: null, error: caught instanceof Error ? caught.message : 'search failed' })
    }
  }, [requests])

  const close = useCallback(() => {
    setOpen(false)
    //? a closed panel's search can never be seen - reopening always searches afresh - so let
    //? it go, which stops it in slskd too
    requests.supersede()
  }, [requests])

  //? how the vanilla Find buttons reach this panel until the releases grid is ported
  useEffect(() => {
    const shared = bridge()
    shared.openCandidates = (release, text) => {
      setLabel(text)
      //? the last album's query, left in the box, would be taken for an edit by Re-search
      setQuery('')
      setShownQuery('')
      setOpen(true)
      void run(release, '')
    }
    return () => { delete shared.openCandidates }
  }, [run])

  useEffect(() => {
    if (!open) return
    const onKey = (event: KeyboardEvent) => { if (event.key === 'Escape') close() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [open, close])

  const requery = () => {
    if (search) void run(search.release, queryOverride(query, shownQuery))
  }

  const download = async (candidate: Candidate) => {
    if (!search?.result) return
    const key = candidateKey(candidate)
    const release = search.release
    setDownloads((current) => new Map(current).set(key, 'queueing'))

    try {
      await requestDownload({
        username: candidate.username,
        files: candidate.files,
        directory: candidate.directory,
        //? the release this candidate was SEARCHED for - never "whichever panel is open now"
        release: { ...release },
      })
      setDownloads((current) => new Map(current).set(key, 'queued'))
    } catch (caught) {
      console.error(`Enqueue error: ${caught instanceof Error ? caught.message : caught}`)
      setDownloads((current) => new Map(current).set(key, 'failed'))
    }
  }

  const formats = useMemo(() => resultFormats(search?.result?.candidates ?? []), [search])
  const toggleFormat = (format: string) => setFilters((current) => {
    const next = new Set(current.formats)
    if (next.has(format)) next.delete(format)
    else next.add(format)
    return { ...current, formats: next }
  })

  return (
    <div id="candidates-window" class={open ? 'open' : ''}>
      <div id="candidates-panel">
        <div id="candidates-header">
          <h3 class="text default">Soulseek candidates</h3>
          <button type="button" id="candidates-close-button" onClick={close}>✕</button>
        </div>
        <hr />
        <div id="candidates-subject">
          <h4 class="text white" id="candidates-release-label">{label}</h4>
          <div id="candidates-query-row">
            <span class="text default-muted candidates-query-label">Query</span>
            <input
              type="text"
              id="candidates-query-input"
              class="releases-filter-input"
              value={query}
              //? every name it was searched under, where there was more than one
              title={(search?.result?.queries?.length ?? 0) > 1
                ? `Also searched as: ${search!.result!.queries!.slice(1).join(' · ')}`
                : ''}
              onInput={(event) => setQuery((event.target as HTMLInputElement).value)}
              onKeyDown={(event) => { if (event.key === 'Enter') requery() }}
            />
            <button type="button" id="candidates-requery-button" class="columns-toggle-button" onClick={requery}>
              Re-search
            </button>
          </div>
          <div id="candidate-filters">
            <label class="candidate-filter-toggle">
              <input
                type="checkbox"
                id="candidate-free-slot-only"
                checked={filters.freeSlotOnly}
                onChange={(event) => {
                  const checked = (event.target as HTMLInputElement).checked
                  setFilters((current) => ({ ...current, freeSlotOnly: checked }))
                }}
              />
              <span class="text default-secondary">Free slot only</span>
            </label>
            <label class="candidate-filter-toggle">
              <input
                type="checkbox"
                id="candidate-complete-only"
                checked={filters.completeOnly}
                onChange={(event) => {
                  const checked = (event.target as HTMLInputElement).checked
                  setFilters((current) => ({ ...current, completeOnly: checked }))
                }}
              />
              <span class="text default-secondary">Complete albums only</span>
            </label>
            <label class="candidate-filter-range">
              <span class="text default-secondary">Min score</span>
              <input
                type="range"
                id="candidate-min-score"
                min="0" max="100" step="5"
                value={filters.minScore}
                onInput={(event) => {
                  const value = Number((event.target as HTMLInputElement).value)
                  setFilters((current) => ({ ...current, minScore: value }))
                }}
              />
              <span class="text default" id="candidate-min-score-value">{filters.minScore}</span>
            </label>
            <div id="candidate-format-filters">
              {formats.map((format) => (
                <button
                  key={format}
                  type="button"
                  class={`tag-chip main${filters.formats.has(format) ? ' active' : ''}`}
                  onClick={() => toggleFormat(format)}
                >
                  {format}
                </button>
              ))}
            </div>
            <SignalsControl filters={filters} setFilters={setFilters} />
          </div>
        </div>
        <div class="scrollable" id="candidates-scrollable">
          <CandidatesBody search={search} filters={filters} downloads={downloads} onDownload={download} />
        </div>
      </div>
    </div>
  )
}

/*
 * Per-signal thresholds in a dropdown rather than inline: six always-visible sliders ate most
 * of the panel, and this is a tuning control you reach for occasionally. The badge keeps an
 * active threshold from becoming hidden state.
 */
function SignalsControl(
  { filters, setFilters }:
  { filters: CandidateFilters; setFilters: (update: (current: CandidateFilters) => CandidateFilters) => void },
) {
  const [open, setOpen] = useState(false)
  const root = useRef<HTMLDivElement>(null)
  const active = activeSignalCount(filters)

  useEffect(() => {
    if (!open) return
    const onClick = (event: MouseEvent) => {
      if (!root.current?.contains(event.target as Node)) setOpen(false)
    }
    document.addEventListener('click', onClick)
    return () => document.removeEventListener('click', onClick)
  }, [open])

  const setMinimum = (signal: string, value: number) => setFilters((current) => ({
    ...current, minSignals: { ...current.minSignals, [signal]: value },
  }))

  return (
    <div
      ref={root}
      class={`releases-columns-control${open ? ' open' : ''}${active ? ' has-active' : ''}`}
      id="candidate-signals-control"
    >
      <button
        type="button"
        id="candidate-signals-button"
        class="columns-toggle-button"
        onClick={(event) => { event.stopPropagation(); setOpen((o) => !o) }}
      >
        Signals ▾
        {active > 0 && <span id="candidate-signals-badge" class="signals-badge">{active}</span>}
      </button>
      <div class="columns-dropdown" id="candidate-signal-sliders">
        {Object.entries(SIGNAL_LABELS).map(([signal, name]) => {
          const value = filters.minSignals[signal] ?? 0
          return (
            <label key={signal} class={`candidate-signal-slider${value > 0 ? ' active' : ''}`}>
              <span class="text default-secondary">{name}</span>
              <input
                type="range" min="0" max="100" step="5"
                value={value}
                onInput={(event) => setMinimum(signal, Number((event.target as HTMLInputElement).value))}
                onClick={(event) => event.stopPropagation()}
              />
              <span class="text default candidate-signal-value">{value}</span>
            </label>
          )
        })}
        <button
          type="button"
          class="signals-reset-button"
          onClick={(event) => {
            event.stopPropagation()
            setFilters((current) => ({ ...current, minSignals: noSignalMinimums() }))
          }}
        >
          Reset
        </button>
      </div>
    </div>
  )
}

/*
 * Whatever state the search is in - so a filter ticked mid-search redraws the "Searching" panel
 * it is already showing, and the answer, when it lands, is drawn through the filters as they
 * are THEN rather than as they were when the search began.
 */
function CandidatesBody(
  { search, filters, downloads, onDownload }:
  {
    search: Search | null
    filters: CandidateFilters
    downloads: ReadonlyMap<string, DownloadState>
    onDownload: (candidate: Candidate) => void
  },
) {
  if (!search) return null

  if (search.pending) {
    return <div class="loading-panel">Searching Soulseek for this release…</div>
  }

  if (search.error) {
    return <h4 class="text red candidates-status">search failed: {search.error}</h4>
  }

  const { candidates, response_count: responses, queries } = search.result!

  if (!candidates.length) {
    //? what was actually searched, when it was more than the box shows: "no matches" after
    //? trying both Kanye West and Ye is a different fact from after trying one
    const searched = (queries?.length ?? 0) > 1
      ? ` (searched as ${queries!.map((q) => `"${q}"`).join(' and ')})`
      : ''
    return (
      <h4 class="text default-muted candidates-status">
        no matches from {responses} responses{searched} — try editing the query above
      </h4>
    )
  }

  const visible = candidates.filter((candidate) => passesFilters(candidate, filters))

  if (!visible.length) {
    return (
      <h4 class="text default-muted candidates-status">
        {candidates.length} candidates, none match your filters
      </h4>
    )
  }

  return (
    <>
      {visible.map((candidate) => (
        <CandidateRow
          key={candidateKey(candidate)}
          candidate={candidate}
          state={downloads.get(candidateKey(candidate))}
          onDownload={onDownload}
        />
      ))}
    </>
  )
}

function CandidateRow(
  { candidate, state, onDownload }:
  { candidate: Candidate; state: DownloadState | undefined; onDownload: (candidate: Candidate) => void },
) {
  const percent = Math.round(candidate.score * 100)
  const size = formatSize(candidate.total_size)
  const measured = measuredSpeed(candidate)

  return (
    <div class={`candidate-box${state === 'queued' ? ' queued' : ''}`}>
      <div class="candidate-main">
        <div class={`candidate-score ${scoreClass(percent)}`}>{percent}</div>
        <div class="candidate-body">
          <h4 class="text white candidate-dir" title={candidate.directory}>{candidate.directory_name}</h4>
          <div class="candidate-meta">
            <span class="text default-secondary">{candidate.username}</span>
            <span class="text default-muted">·</span>
            <span class="text default-secondary">{trackSummary(candidate)}</span>
            <span class="text default-muted">·</span>
            <span class="text default-secondary">
              {(candidate.formats.join(', ') || 'unknown') + bitrateText(candidate.bitrates)}
            </span>
            {size && (
              <>
                <span class="text default-muted">·</span>
                <span class="text default-secondary">{size}</span>
              </>
            )}
          </div>
          <div class="candidate-peer">
            {measured && <span class="candidate-measured" title={measured.title}>{measured.text}</span>}
            <span class="candidate-speed" title={PEER_SPEED_HINT}>{peerSpeedLabel(candidate.upload_speed)}</span>
            <span class={`candidate-slot ${candidate.has_free_slot ? 'free' : 'busy'}`}>
              {candidate.has_free_slot ? 'free slot' : 'no free slot'}
            </span>
            <span class="text default-muted">queue {candidate.queue_length}</span>
          </div>
          <div class="candidate-tags">
            {candidate.detected_edition_tags.map((tag) => (
              <h4 key={tag} class={`text ${EDITION_TAG_COLORS[tag] ?? 'default'} edition-tag`}>{tag}</h4>
            ))}
          </div>
          <div class="candidate-signals">
            {Object.entries(candidate.signals)
              .filter(([, value]) => value !== null)
              .map(([name, value]) => {
                const pct = Math.round((value as number) * 100)
                return (
                  <span key={name} class={`candidate-signal ${scoreClass(pct)}`}>
                    {SIGNAL_LABELS[name] ?? name} {pct}
                  </span>
                )
              })}
          </div>
        </div>
        <button
          type="button"
          class="candidate-download-button"
          disabled={state === 'queueing' || state === 'queued'}
          onClick={() => onDownload(candidate)}
        >
          {state === 'queueing' ? 'Queueing…' : state === 'queued' ? 'Queued ✓' : state === 'failed' ? 'Failed' : 'Download'}
        </button>
      </div>
    </div>
  )
}
