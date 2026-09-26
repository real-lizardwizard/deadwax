import { get, post } from './http'
import type {
  CancelJobResponse,
  ClearJobsResponse,
  EnqueueRequest,
  EnqueueResponse,
  FindCandidatesRequest,
  FindCandidatesResponse,
  JobsResponse,
} from './types'

/**
 * Search Soulseek for a release. Aborting it (the signal) also stops the search in slskd - the
 * server notices the dropped connection (unless_abandoned in routes/download.py).
 */
export function findCandidates(
  body: FindCandidatesRequest, signal?: AbortSignal,
): Promise<FindCandidatesResponse> {
  return post<FindCandidatesResponse>('/download/find_candidates', body, signal)
}

export function enqueue(body: EnqueueRequest): Promise<EnqueueResponse> {
  return post<EnqueueResponse>('/download/enqueue', body)
}

/** Stored jobs merged with live progress from slskd. Safe to poll; see useDownloadJobs. */
export function listJobs(): Promise<JobsResponse> {
  return get<JobsResponse>('/download/jobs')
}

export function cancelJob(jobId: number): Promise<CancelJobResponse> {
  return post<CancelJobResponse>(`/download/jobs/${jobId}/cancel`)
}

/** Forgets finished jobs only - anything still moving is left alone by the server. */
export function clearJobs(): Promise<ClearJobsResponse> {
  return post<ClearJobsResponse>('/download/jobs/clear')
}
