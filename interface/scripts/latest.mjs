/**
 * Only the newest answer counts.
 *
 * Reported as "it's as if it can't handle more than one action at once": untick "free slot"
 * while a Soulseek search is running and the panel showed the PREVIOUS search's results; open a
 * second album's candidates before the first had answered, and whichever search came back last
 * was drawn - under the second album's name, and enqueued as the second album's release. Every
 * one of those was an answer applied without asking whether it still answered the question on
 * screen. Nothing here was ever unable to do two things at once; it was unable to tell them
 * apart.
 *
 * So anything that fetches and then draws goes through one of these. `begin()` starts a request
 * and supersedes whatever came before it - aborting its fetch, which gives the browser its
 * connection back (a Soulseek search holds one for as long as it takes) - and hands back a
 * `current()` to ask once the answer arrives. Anything no longer current is dropped, quietly:
 * a superseded request failing is not an error anybody needs to see, so the catch asks too.
 *
 * `supersede()` is for the times something else takes over without a request of its own - a
 * cached search drawn in the same tick, a panel closed.
 *
 * Pure apart from AbortController, `.mjs` so ui/test/latest.sim.cjs can hold it to account.
 * ui/src/lib/latest.ts is the Preact half's copy and the sim checks both.
 */
export function latestOnly() {
  let newest = 0;
  let controller = null;

  function supersede() {
    newest += 1;
    controller?.abort();
    controller = null;
  }

  return {
    begin() {
      supersede();
      const ticket = newest;
      controller = typeof AbortController === 'function' ? new AbortController() : null;
      return {
        signal: controller?.signal,
        current: () => ticket === newest,
      };
    },
    supersede,
  };
}

/** Whether `error` is only a fetch being called off - never worth reporting. */
export function isAbort(error) {
  return error?.name === 'AbortError';
}
