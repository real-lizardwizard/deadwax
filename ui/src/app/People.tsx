import { useEffect, useMemo, useRef, useState } from 'preact/hooks'

import { forgetPerson, lockPeople, savePermissions, setAdmin, type KnownOnly, type Person } from '../api/people'
import { MANAGING_ADMINS_ONLY } from '../lib/appRoutes'
import { latestOnly } from '../lib/latest'
import {
  KNOWN_ONLY_LINE, KNOWN_ONLY_TITLE, SHARING_DOC, UNLOCKED_LINE, actions, chips, knownWords, librariesWarning, libraryWords,
  makeAdminWords, peopleView, refusals, signInWords, unmakeAdminWords, versionNote,
} from '../lib/people'
import { CATEGORIES, LABELS, PEOPLE_LINE, changed, checkboxes, lockedReason, savedWords, type Category } from '../lib/permissions'
import { navidromeStatus } from '../player/api'
import { ChevronLeftIcon } from '../player/icons'
import { AddPerson } from './AddPerson'
import { ConfirmLine } from './ConfirmLine'
import { RemovePerson } from './RemovePerson'
import { ResetPassword } from './ResetPassword'
import { UnlockPeople } from './UnlockPeople'
import { refusalOf, usePeople } from './usePeople'

/**
 * People (2.0.0-player.61): Navidrome's accounts, managed from deadwax - a Managing page beside Needs a look, Library
 * care, Server settings and the Log, on both frames (You → Managing deadwax → People on a phone, the sidebar's
 * Managing group on a desktop). A Navidrome admin's, with logins on; someone without it gets a short note.
 *
 * Everything is done in Navidrome AS YOU, with your own Navidrome JWT - so People opens LOCKED, and you unlock it
 * with your own password (UnlockPeople.tsx), on this device, for 15 minutes since you last use it; Lock ends it.
 * Unlocked: Add a person (AddPerson.tsx), and every account Navidrome has - who they are, their deadwax sign-ins
 * and library, the ways to change them (Reset password…, Make admin / No longer admin, Remove…) each with its
 * reason when People refuses it (the server's `can`), and an ordinary person's Permissions - five checkboxes,
 * saved with Save permissions, never per tick. Under the list, Known only to deadwax: names deadwax keeps things
 * for with no Navidrome account, each with Forget. Nothing here plays (app-rules.sim.cjs).
 */
export function People({
  allowed,
  live,
  onBack,
  backLabel,
}: {
  /** People's permission: a Navidrome admin's (with logins off, `local` has it - and the page says why it can't work) */
  allowed: boolean
  /** the page is what shows: its tab current, the app in front, nothing over it */
  live: boolean
  onBack: () => void
  backLabel: string
}) {
  const { state, problem, ask, locked } = usePeople(live, allowed)
  const [said, setSaid] = useState<string | null>(null)
  const [server, setServer] = useState<string | null>(null)
  const versions = useMemo(latestOnly, [])
  const view = peopleView(state)

  //? Navidrome's version, for the note when it isn't the one People was made for - asked once it is unlocked
  useEffect(() => {
    if (!allowed || !live || view !== 'list') return
    const request = versions.begin()
    navidromeStatus(request.signal).then((status) => {
      if (request.current()) setServer(status.server)
    }, () => {})
    return () => versions.supersede()
  }, [allowed, live, view])

  const header = (
    <>
      <header class="pl-nav-bar">
        <button type="button" class="pl-back" onClick={onBack}>
          <ChevronLeftIcon class="pl-back-icon" />
          <span class="pl-back-label">{backLabel}</span>
        </button>
      </header>
      <header class="pl-large-header">
        <h1 class="pl-large-title">People</h1>
      </header>
    </>
  )

  if (!allowed) {
    return (
      <section class="app-people is-refused app-needs">
        {header}
        <div class="app-card app-placeholder-body">
          <p class="app-placeholder-text">{MANAGING_ADMINS_ONLY}</p>
        </div>
      </section>
    )
  }

  const lock = () => {
    void lockPeople().then(ask, ask)
  }
  const changedSome = (words: string) => {
    setSaid(words)
    ask()
  }
  const note = view === 'list' ? versionNote(server) : null

  return (
    <section class="app-people">
      {header}
      <div class="app-people-body">
        <div aria-live="polite" aria-atomic="true">
          {said && <p class="app-people-done" role="status">{said}</p>}
        </div>
        {problem && <p class="app-people-problem" role="alert">{problem}</p>}
        {view === 'asking' && !problem && <div class="pl-spinner" aria-label="Asking deadwax" />}

        {state && state.problem && (
          <div class="app-card app-people-state">
            <p class="app-people-line">{state.problem}</p>
            {state.fix && <p class="app-footnote">{state.fix}</p>}
            {!state.on && (
              <p class="app-footnote">
                <a class="app-text-button" href={SHARING_DOC} target="_blank" rel="noopener">Sharing deadwax</a>
              </p>
            )}
          </div>
        )}

        {view === 'locked' && state && <UnlockPeople user={state.you} onUnlocked={ask} />}

        {view === 'list' && state && (
          <>
            <div class="app-people-lockline">
              <p class="app-footnote">{UNLOCKED_LINE}</p>
              <button type="button" class="app-button app-people-lock" onClick={lock}>Lock</button>
            </div>
            {note && <p class="app-footnote app-people-version">{note}</p>}
            <AddPerson onMade={ask} onLocked={locked} />
            <section class="app-people-section" aria-labelledby="app-people-list-title">
              <h2 id="app-people-list-title" class="app-section-title">Everyone in Navidrome</h2>
              <ul class="app-people-list">
                {state.people.map((person) => (
                  <PersonRow key={person.id} person={person} onChanged={changedSome} onLocked={locked} />
                ))}
              </ul>
            </section>
            {state.known_only.length > 0 && (
              <section class="app-people-section" aria-labelledby="app-people-known-title">
                <h2 id="app-people-known-title" class="app-section-title">{KNOWN_ONLY_TITLE}</h2>
                <p class="app-footnote">{KNOWN_ONLY_LINE}</p>
                <ul class="app-people-list">
                  {state.known_only.map((entry) => (
                    <KnownOnlyRow key={entry.user} entry={entry} onChanged={changedSome} onLocked={locked} />
                  ))}
                </ul>
              </section>
            )}
          </>
        )}
      </div>
    </section>
  )
}

type Open = 'reset' | 'admin' | 'remove' | null

/** One account: who, what deadwax knows of them, and what can be done - each refusal said in words. */
function PersonRow({ person, onChanged, onLocked }: { person: Person; onChanged: (words: string) => void; onLocked: () => void }) {
  const [open, setOpen] = useState<Open>(null)
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const removeButton = useRef<HTMLButtonElement>(null)
  const sending = useRef(false)
  const warning = librariesWarning(person)
  const offered = actions(person)
  const reasons = refusals(person)
  const ticked = person.permissions ? CATEGORIES.filter((category) => person.permissions![category]).map((category) => LABELS[category]) : []
  const words = person.admin ? unmakeAdminWords(person.user, ticked) : makeAdminWords(person.user)

  const flip = () => {
    if (sending.current) return
    sending.current = true
    setBusy(true)
    setProblem(null)
    setAdmin(person.id, { user: person.user, admin: !person.admin }).then(
      (answer) => {
        sending.current = false
        setBusy(false)
        setOpen(null)
        onChanged(answer.admin ? `${answer.user} is an admin now.` : `${answer.user} is no longer an admin.`)
      },
      (reason: unknown) => {
        sending.current = false
        setBusy(false)
        const refusal = refusalOf(reason)
        setProblem(refusal.words)
        if (refusal.locked) onLocked()
      },
    )
  }

  return (
    <li class="app-card app-people-row">
      <div class="app-people-who">
        <span class="app-people-name">{person.name}</span>
        <span class="app-people-user app-mono">{person.user}</span>
        {chips(person).map((chip) => <span key={chip} class="app-people-chip">{chip}</span>)}
      </div>
      <p class="app-people-fact">{signInWords(person, Date.now() / 1000)}</p>
      <p class="app-people-fact">{libraryWords(person)}</p>
      {warning && <p class="app-people-warning">{warning}</p>}
      <div class="app-people-actions">
        {offered.filter((action) => !action.refused).map((action) => (
          <button
            key={action.kind}
            {...(action.kind === 'remove' ? { ref: removeButton } : {})}
            type="button"
            class={`app-button app-people-action${action.kind === 'remove' ? ' is-danger' : ''}`}
            aria-expanded={open === action.kind}
            onClick={() => {
              setProblem(null)
              setOpen(open === action.kind ? null : action.kind)
            }}
          >
            {action.label}
          </button>
        ))}
      </div>
      {reasons.map((reason) => <p key={reason} class="app-footnote app-people-reason">{reason}</p>)}
      {open === 'reset' && (
        <ResetPassword person={person} onDone={(done) => { setOpen(null); onChanged(done) }} onCancel={() => setOpen(null)} onLocked={onLocked} />
      )}
      {open === 'admin' && (
        <div class="app-people-inline">
          <p class="app-people-line">{words.body}</p>
          <ConfirmLine
            words={words.question}
            confirm={person.admin ? 'No longer admin' : 'Make admin'}
            keep="Keep as it is"
            busy={busy}
            busyLabel="Changing…"
            problem={problem}
            onConfirm={flip}
            onKeep={() => setOpen(null)}
          />
        </div>
      )}
      {open === 'remove' && (
        <RemovePerson
          person={person}
          onRemoved={(done) => { setOpen(null); onChanged(done) }}
          onCancel={() => {
            setOpen(null)
            removeButton.current?.focus({ preventScroll: true })
          }}
          onLocked={() => { setOpen(null); onLocked() }}
        />
      )}
      <PersonPermissions person={person} onChanged={onChanged} onLocked={onLocked} />
    </li>
  )
}

/** An ordinary person's Permissions: five checkboxes and Save permissions; an admin's all ticked and locked; a row
 *  People refuses them for (you, deadwax's own account, a reserved name) locked with its reason. */
function PersonPermissions({ person, onChanged, onLocked }: { person: Person; onChanged: (words: string) => void; onLocked: () => void }) {
  const [draft, setDraft] = useState<Record<Category, boolean> | null>(person.permissions)
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const sending = useRef(false)
  //? what was saved, as the list said it - a fresh list puts the draft back to it
  useEffect(() => setDraft(person.permissions), [JSON.stringify(person.permissions)])
  const refused = person.can.permissions
  const boxes = checkboxes(person.admin, refused, draft)
  const reason = lockedReason(person.admin, refused)
  const dirty = changed(person.permissions, draft)

  const save = () => {
    if (!draft || !dirty || sending.current) return
    sending.current = true
    setBusy(true)
    setProblem(null)
    savePermissions(person.id, { user: person.user, ...draft }).then(
      () => {
        sending.current = false
        setBusy(false)
        onChanged(savedWords(person.user))
      },
      (caught: unknown) => {
        sending.current = false
        setBusy(false)
        const refusal = refusalOf(caught)
        setProblem(refusal.words)
        if (refusal.locked) onLocked()
      },
    )
  }

  return (
    <fieldset class="app-people-permissions">
      <legend class="app-people-label">Permissions</legend>
      {reason && <p class="app-footnote app-people-reason">{reason}</p>}
      {boxes.map((box) => (
        <label key={box.category} class={`app-people-check app-people-permission${box.locked ? ' is-locked' : ''}`}>
          <input
            type="checkbox"
            class="app-people-checkbox"
            checked={box.checked}
            disabled={box.locked}
            onChange={(event) => {
              const on = (event.currentTarget as HTMLInputElement).checked
              setDraft((was) => (was ? { ...was, [box.category]: on } : was))
            }}
          />
          <span class="app-people-permission-text">
            <span class="app-people-permission-label">{box.label}</span>
            <span class="app-footnote">{box.line}</span>
            {box.warning && <span class="app-people-warning">{box.warning}</span>}
          </span>
        </label>
      ))}
      <p class="app-footnote app-people-permission-people">{PEOPLE_LINE}</p>
      {!person.admin && !refused && (
        <div class="app-people-buttons">
          <button type="button" class="app-button is-primary" aria-disabled={!dirty || busy} onClick={save}>
            {busy ? 'Saving…' : 'Save permissions'}
          </button>
        </div>
      )}
      <div aria-live="assertive" aria-atomic="true">
        {problem && <p class="app-people-problem" role="alert">{problem}</p>}
      </div>
    </fieldset>
  )
}

/** A name deadwax keeps things for with no Navidrome account: what is kept, and Forget. */
function KnownOnlyRow({ entry, onChanged, onLocked }: { entry: KnownOnly; onChanged: (words: string) => void; onLocked: () => void }) {
  const [asking, setAsking] = useState(false)
  const [busy, setBusy] = useState(false)
  const [problem, setProblem] = useState<string | null>(null)
  const sending = useRef(false)

  const forget = () => {
    if (sending.current) return
    sending.current = true
    setBusy(true)
    setProblem(null)
    forgetPerson(entry.user).then(
      () => {
        sending.current = false
        setBusy(false)
        onChanged(`deadwax forgot what it kept for ${entry.user}.`)
      },
      (reason: unknown) => {
        sending.current = false
        setBusy(false)
        const refusal = refusalOf(reason)
        setProblem(refusal.words)
        if (refusal.locked) onLocked()
      },
    )
  }

  return (
    <li class="app-card app-people-row">
      <div class="app-people-who">
        <span class="app-people-user app-mono">{entry.user}</span>
      </div>
      <p class="app-people-fact">{knownWords(entry)}</p>
      {asking ? (
        <ConfirmLine
          words={`Forget what deadwax keeps for ${entry.user}? Their library list, pins, settings and permissions go - the albums stay in the store.`}
          confirm="Forget"
          keep="Keep it"
          danger
          busy={busy}
          busyLabel="Forgetting…"
          problem={problem}
          onConfirm={forget}
          onKeep={() => setAsking(false)}
        />
      ) : (
        <div class="app-people-actions">
          <button type="button" class="app-button app-people-action" onClick={() => setAsking(true)}>Forget…</button>
        </div>
      )}
    </li>
  )
}
