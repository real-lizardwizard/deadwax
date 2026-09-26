import * as api from '../api/download'
import type { EnqueueRequest, EnqueueResponse } from '../api/types'

/**
 * "Queue this download", from anywhere in the bundle, handled by the downloads panel.
 *
 * The panel owns the optimistic row a download shows as from the click (v0.9.9), but the
 * candidates panel that asks for it is a separate render tree, and a hook's state can't be
 * reached from another tree. So the panel registers its enqueue here while it is mounted, the
 * same arrangement as lib/libraryEvents.ts - a module, not a bridge entry, because both sides
 * are in this bundle. With no panel mounted it falls back to a plain request.
 */

type Enqueue = (body: EnqueueRequest) => Promise<EnqueueResponse>

let handler: Enqueue | null = null

/** Handle every download request from now on. Returns the unregister, for an effect. */
export function handleDownloadRequests(enqueue: Enqueue): () => void {
  handler = enqueue
  return () => {
    if (handler === enqueue) handler = null
  }
}

export function requestDownload(body: EnqueueRequest): Promise<EnqueueResponse> {
  return handler ? handler(body) : api.enqueue(body)
}
