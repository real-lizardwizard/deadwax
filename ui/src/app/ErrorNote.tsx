import { errorWords, said, type ErrorOptions } from '../lib/errorWords'
import { accessNow, seesDetail } from './access'

/**
 * (2.0.4) An error line, in a listener's words (lib/errorWords.ts): what happened and what to do, and - for
 * someone who runs deadwax (an admin, or someone with Settings and the log: access.ts seesDetail) - the error's
 * own words under it, smaller. Every page's `{error}` line draws through these (errors.sim holds the pages to
 * them), so no listener is shown a raw exception, address or setting name again.
 *
 * FUNCTIONS, not components, on purpose: what they draw is the page's own <p> or <span>, so a page's words are its
 * own (the sims read them as they read the rest), and they call no hook - so a page may call one conditionally
 * (`{error ? errorNote(error) : null}`) without changing its hooks' order. Who is reading is what /me last said
 * (access.ts accessNow); a page drawn again as that changes says it the new way.
 *
 * `as` is the element the sentence is: a <p> by default, a <span> inside a row.
 */
export function errorNote(
  error: unknown,
  { class: className = '', as = 'p', ...options }: { class?: string; as?: 'p' | 'span' } & Omit<ErrorOptions, 'admin'> = {},
) {
  const words = errorWords(error, { ...options, admin: seesDetail(accessNow()) })
  return errorLine(said(words), words.detail, { class: className, as })
}

/** The line itself, for words worked out elsewhere (a download's reason): the sentence, and the detail under it. */
export function errorLine(
  text: string,
  detail: string | null | undefined,
  { class: className = '', as = 'p' }: { class?: string; as?: 'p' | 'span' } = {},
) {
  const under = detail ? <span class="app-error-detail">{detail}</span> : null
  return as === 'span' ? (
    <span class={className}>
      {text}
      {under}
    </span>
  ) : (
    <p class={className}>
      {text}
      {under}
    </p>
  )
}

