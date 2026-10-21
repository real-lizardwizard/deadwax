import { useCallback, useEffect, useMemo, useState } from 'preact/hooks'

import { ApiError } from '../api/http'
import { getPeople, type PeopleState } from '../api/people'
import { isAbort, latestOnly } from '../lib/latest'

/**
 * People's state (2.0.0-player.61): `GET /deadwax/people`, asked as the page shows and after every change - through
 * latestOnly(), so only the newest answer draws. Read fresh each time (no cache): a change made in Navidrome's own
 * Users page shows at the next ask. Nothing is asked for someone without the permission.
 */
export function usePeople(live: boolean, allowed: boolean): {
  state: PeopleState | null
  problem: string | null
  ask: () => void
  /** a People route said `locked`: the unlock form comes back at once, and the page asks again */
  locked: () => void
} {
  const [state, setState] = useState<PeopleState | null>(null)
  const [problem, setProblem] = useState<string | null>(null)
  const requests = useMemo(latestOnly, [])

  const ask = useCallback(() => {
    const request = requests.begin()
    getPeople(request.signal).then(
      (answer) => {
        if (!request.current()) return
        setState(answer)
        setProblem(null)
      },
      (reason: unknown) => {
        if (!request.current() || isAbort(reason)) return
        setProblem(reason instanceof Error ? reason.message : String(reason))
      },
    )
  }, [])

  const locked = useCallback(() => {
    setState((was) => (was ? { ...was, locked: true, people: [], known_only: [] } : was))
    ask()
  }, [])

  useEffect(() => {
    if (!live || !allowed) return
    ask()
    return () => requests.supersede()
  }, [live, allowed])

  return { state, problem, ask, locked }
}

/** A refusal's words - and whether it was People saying it is locked again. */
export function refusalOf(reason: unknown): { words: string; locked: boolean } {
  if (reason instanceof ApiError) return { words: reason.message, locked: reason.kind === 'locked' }
  return { words: reason instanceof Error ? reason.message : String(reason), locked: false }
}
