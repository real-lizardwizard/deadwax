import type { DownloadJob, JobStatus } from '../api/types'

/**
 * Statuses that mean work is outstanding.
 *
 * `organizing` is included even though the server's OPEN_STATUSES (src/store.py) excludes
 * it: the server uses that set to decide whether to ask slskd for transfers, which is
 * pointless once downloading is done, whereas the UI needs to keep polling through the
 * filing step or the panel goes quiet before the job actually finishes.
 */
export const ACTIVE_STATUSES: ReadonlySet<JobStatus> = new Set<JobStatus>([
  'queued',
  'downloading',
  'organizing',
])

export function isActive(job: DownloadJob): boolean {
  return ACTIVE_STATUSES.has(job.status)
}
