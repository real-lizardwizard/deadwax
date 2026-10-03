import { useMemo, useRef, useState } from 'preact/hooks'

import * as api from '../api/download'
import type { Candidate, DownloadRelease, FindCandidatesResponse } from '../api/types'
import { autoGrabPick, autoPickBlocked, candidateKey, queryOverride, type CandidateFilters, type CandidateSort } from '../lib/candidates'
import { requestDownload } from '../lib/downloadRequests'
import { notPickedLine } from '../lib/getSettings'
import { isAbort, latestOnly } from '../lib/latest'
import { readDownloadDefaults } from '../state/persisted'

/**
 * One Soulseek search for a release, and a download from it - the app's Sources sheet's
 * (2.0.0-player.15). The main page's candidates panel (components/CandidatesPanel.tsx) does the
 * same orchestration and is left exactly as it is - so the main page, and merges from main into it,
 * stay safe; the copy goes when the main page does. Every rule it relies on is in the shared, tested
 * lib/candidates.ts and lib/latest.ts:
 *
 *  - ONE search value, which only the newest search becomes (latestOnly, v0.9.2): a slow answer for
 *    the album you left never draws under the album you went to, and the search it superseded is
 *    called off (which stops it in slskd too).
 *  - Each candidate downloads as the release IT was searched for - the search's own, never
 *    "whatever the sheet is showing now".
 *  - Only an EDITED query overrides a Re-search (queryOverride): the box shows the first of the
 *    names searched, and re-running it as typed would quietly drop the rest.
 *  - "Pick the best source for me" acts only on a FRESH Get - never a Re-search you are steering by
 *    hand - and never for a pressing held or on its way (autoPickBlocked, read off the answer
 *    itself), nor for a release with no tracklist or no release id - the album as a whole, when
 *    MusicBrainz couldn't list its pressings - where the score is edition, format and peer alone and
 *    75 means nothing (review); it takes the top of the list through the filters by best match, only
 *    at AUTO_GRAB_MIN_SCORE or better (autoGrabPick), and when nothing qualifies it says why
 *    (`notPicked`) and leaves the sources showing.
 *  - A download sends up to ten runners-up, as they are SHOWN (filters and sort), for "next peer".
 *  - The main panel clears its format chips per search; the sheet has none - its chips are a
 *    quality floor's, which hold across searches as a choice of yours.
 *
 * `picking` is read when an answer lands, not when the search began: the settings and the chips as
 * they are THEN, as the main panel reads its filters. `onPicked` is told when a pick has been asked
 * for, so the sheet can hand over to Requests as a tapped Get does.
 */

export interface CandidateSearch {
  /** what this search is for - and what a download from it files as */
  release: DownloadRelease
  pending: boolean
  result: FindCandidatesResponse | null
  /** what went wrong, in the server's words where it gave some (slskd logged out: its 409's) */
  error: string | null
}

export interface PickRule {
  /** "When I tap Get" is "Pick the best source for me" */
  pick: boolean
  filters: CandidateFilters
  sort: CandidateSort
}

export interface CandidateSearchState {
  search: CandidateSearch | null
  /** the query box (the no-sources state's): what it says now, and what the search said */
  query: string
  setQuery: (text: string) => void
  /** why a pick wasn't made, when one was wanted */
  notPicked: string | null
  /** a fresh Get: search for `release`, and pick if the settings say so */
  start: (release: DownloadRelease) => void
  /** search the same release again - with the box's query only when it was edited */
  requery: () => void
  /** let the search go: the sheet closed (which stops it in slskd too) */
  stop: () => void
  /**
   * Download `candidate` as the search's release, with the list as SHOWN for runners-up. Called
   * in the tap; the pending row in Requests is up from this call. False when this search has
   * already asked for one (a second tap before the sheet closed).
   */
  download: (candidate: Candidate, shown: readonly Candidate[]) => boolean
}

export function useCandidateSearch({ picking, onPicked }: {
  picking: () => PickRule
  onPicked: () => void
}): CandidateSearchState {
  const [search, setSearch] = useState<CandidateSearch | null>(null)
  const [query, setQuery] = useState('')
  const [shownQuery, setShownQuery] = useState('')
  const [notPicked, setNotPicked] = useState<string | null>(null)
  const requests = useMemo(latestOnly, [])
  //? the search that has asked for a download: one download per search, however fast the taps
  const askedFor = useRef<DownloadRelease | null>(null)
  //? read when an answer lands - this render's, never the one that began the search
  const pickingNow = useRef(picking)
  pickingNow.current = picking
  const pickedNow = useRef(onPicked)
  pickedNow.current = onPicked

  function ask(release: DownloadRelease, candidate: Candidate, shown: readonly Candidate[]): boolean {
    if (askedFor.current === release) return false
    askedFor.current = release
    const key = candidateKey(candidate)
    //? in the tap, nothing awaited before it: the downloads hook lays the pending row down here
    requestDownload({
      username: candidate.username,
      files: candidate.files,
      directory: candidate.directory,
      //? the release this candidate was SEARCHED for
      release: { ...release },
      //? the rest of the list as you saw it, in order, for "next peer" (v0.9.12)
      alternatives: shown
        .filter((each) => candidateKey(each) !== key)
        .slice(0, 10)
        .map((each) => ({ username: each.username, directory: each.directory, files: each.files, score: each.score })),
    }).catch((caught: unknown) => {
      //? slskd's refusal, or deadwax's 409, is on the pending row in Requests ("refused: ...")
      console.error(`Enqueue error: ${caught instanceof Error ? caught.message : caught}`)
    })
    return true
  }

  async function run(release: DownloadRelease, override: string, fresh: boolean) {
    const request = requests.begin()
    askedFor.current = null
    setSearch({ release, pending: true, result: null, error: null })
    setNotPicked(null)
    try {
      const result = await api.findCandidates(
        //? read per search, so a format preference changed on the main page applies at once
        { ...release, query_override: override, format_preference: readDownloadDefaults().formatPreference },
        request.signal,
      )
      if (!request.current()) return
      setSearch({ release, pending: false, result, error: null })
      setQuery(result.query)
      setShownQuery(result.query)

      const rule = pickingNow.current()
      if (!fresh || !rule.pick) return
      const blocked = autoPickBlocked(result, release)
      const grab = blocked ? null : autoGrabPick(result.candidates, rule.filters, rule.sort)
      if (grab && ask(release, grab.pick, grab.list)) {
        pickedNow.current()
        return
      }
      setNotPicked(notPickedLine(blocked))
    } catch (caught) {
      if (!request.current() || isAbort(caught)) return
      setSearch({ release, pending: false, result: null, error: caught instanceof Error ? caught.message : 'the search failed' })
    }
  }

  return {
    search,
    query,
    setQuery,
    notPicked,
    start(release) {
      //? the last album's query, left in the box, would be taken for an edit by Re-search
      setQuery('')
      setShownQuery('')
      void run(release, '', true)
    },
    requery() {
      if (search) void run(search.release, queryOverride(query, shownQuery), false)
    },
    stop() {
      requests.supersede()
    },
    download(candidate, shown) {
      return search?.result ? ask(search.release, candidate, shown) : false
    },
  }
}
