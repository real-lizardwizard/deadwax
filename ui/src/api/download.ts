import { get, post } from './http'
import type {
  CancelJobResponse,
  ClearJobsResponse,
  EnqueueRequest,
  EnqueueResponse,
  FindCandidatesRequest,
  FindCandidatesResponse,
  JobsResponse,
  RetryResponse,
  RetrySameResponse,
  StoreStateResponse,
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

/**
 * What the library and the downloads already have of a pressing, WITHOUT searching Soulseek
 * (2.0.0-player.15) - the app's status line under the pressing before Get. The body is the Find's.
 */
export function storeState(body: FindCandidatesRequest, signal?: AbortSignal): Promise<StoreStateResponse> {
  return post<StoreStateResponse>('/download/store_state', body, signal)
}

export function enqueue(body: EnqueueRequest): Promise<EnqueueResponse> {
  return post<EnqueueResponse>('/download/enqueue', body)
}

/** Stored jobs merged with live progress from slskd. Safe to poll; see useDownloadJobs. */
export function listJobs(): Promise<JobsResponse> {
  return get<JobsResponse>('/download/jobs')
}

/** Move a failed or cancelled job to the next peer from the list it was picked from. */
export function retryJob(jobId: number): Promise<RetryResponse> {
  return post<RetryResponse>(`/download/jobs/${jobId}/retry`)
}

/** Ask the same peer for a failed or cancelled job again, for the files that didn't arrive. */
export function retryJobSamePeer(jobId: number): Promise<RetrySameResponse> {
  return post<RetrySameResponse>(`/download/jobs/${jobId}/retry_same`)
}

export function cancelJob(jobId: number): Promise<CancelJobResponse> {
  return post<CancelJobResponse>(`/download/jobs/${jobId}/cancel`)
}

/** Forgets finished jobs only - anything still moving is left alone by the server. */
export function clearJobs(): Promise<ClearJobsResponse> {
  return post<ClearJobsResponse>('/download/jobs/clear')
}
