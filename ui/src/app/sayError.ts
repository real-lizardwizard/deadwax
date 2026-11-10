import { noticeWords, type ErrorOptions } from '../lib/errorWords'
import { accessNow, seesDetail } from './access'

/**
 * (2.0.4) What went wrong as ONE line of words, for a store or a state that keeps words rather than the error (the
 * playlists, Getting albums, a notice): `lead`, the sentence and what to do (lib/errorWords.ts) - and, for whoever
 * runs deadwax as /me last said (access.ts accessNow, seesDetail), the error's own words in brackets after it. No
 * JSX here, so a store needs nothing of Preact's to say it; app/ErrorNote.tsx draws the two-line kind.
 */
export function sayError(error: unknown, lead = '', options: Omit<ErrorOptions, 'admin'> = {}): string {
  return noticeWords(lead, error, { ...options, admin: seesDetail(accessNow()) })
}
