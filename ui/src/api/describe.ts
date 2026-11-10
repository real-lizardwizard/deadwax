import type { DescribeAnswer } from '../lib/describe'
import { get } from './http'

/**
 * (2.0.13) An artist's or an album's description - `key` is lib/describe.ts describeKey's, the route and its
 * query. Always answered: every field null when there is none (src/routes/describe.py).
 */
export function getDescription(key: string, signal?: AbortSignal): Promise<DescribeAnswer> {
  return get<DescribeAnswer>(key, signal)
}
