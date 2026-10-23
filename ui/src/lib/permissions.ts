/**
 * What the app shows by what the person may do (2.0.0-player.61) - pure, so ui/test/permissions.sim.cjs pins
 * every managing part for every single permission and for none.
 *
 * Roles work as Navidrome's do: an ADMIN (a Navidrome admin, or break-glass, or `local` with logins off) has
 * every permission. An ordinary person has Get albums unless an admin took it away, plus what an admin ticked
 * for them in People. /deadwax/me says which (`permissions`, src/users.py PERMISSIONS' order). THE APP ONLY
 * HIDES: every category is enforced per route on the server (src/users.py require), and tests/test_logins.py's
 * walk proves each route refuses every other category.
 */

export type Permission = 'request' | 'edit' | 'library' | 'downloads' | 'server' | 'people'

/** Every permission, in /me's order (src/users.py PERMISSIONS). */
export const PERMISSIONS: readonly Permission[] = ['request', 'edit', 'library', 'downloads', 'server', 'people']

/** The five an admin can tick for an ordinary person, in People's order. `people` is a Navidrome admin's alone. */
export type Category = Exclude<Permission, 'people'>
export const CATEGORIES: readonly Category[] = ['request', 'edit', 'library', 'downloads', 'server']

export type Permissions = ReadonlySet<Permission>

export const ALL: Permissions = new Set(PERMISSIONS)
export const NONE: Permissions = new Set()

/** What each is called - People's checkboxes, and the server's 403 (src/users.py LABELS). */
export const LABELS: Readonly<Record<Permission, string>> = {
  request: 'Get albums',
  edit: 'Edit albums',
  library: 'Look after the library',
  downloads: "Everyone's downloads",
  server: 'Settings and the log',
  people: 'People',
}

/** What each one opens, under its checkbox. */
export const LINES: Readonly<Record<Category, string>> = {
  request: 'Search Soulseek and download - Get, Sources, Next peer, Ask again.',
  edit: 'Tags, covers, CD art, lyrics, artist pictures, applying a release - one album or Library care\'s runs.',
  library: 'Delete albums, move an artist\'s albums, Needs a look, Rescan, Held by nobody.',
  downloads: 'See who asked for what, cancel or retry anyone\'s, clear everyone\'s finished.',
  server: 'The server settings and the event log.',
}

/** People's line where a checkbox would be: it comes with being a Navidrome admin. */
export const PEOPLE_LINE = 'People - Navidrome admins only'
/** A Navidrome admin's row: every box ticked and locked. */
export const ADMINS_EVERYTHING = 'Admins can do everything.'

/** What ticking (or unticking) adds under the box - the near-admin ones said plainly. */
//? (2.0.0-player.65) not slskd or Navidrome: their rows stay an admin's (ADMINS_ONLY in src/routes/settings.py)
export const WARN_SERVER = 'Settings can point deadwax at other folders and change how it downloads and files - give it only to someone you\'d trust as an admin.'
export const WARN_LIBRARY = 'This includes deleting albums from disk, which can\'t be undone.'
export const WARN_NO_REQUEST = 'They can still play, browse and add what the store has.'

/** In Get's place, without Get albums. */
export const GET_OFF = 'Getting albums is off for you - ask an admin.'

/** What a Managing page says, in place of itself, to someone without its permission. */
export const NO_PERMISSION = "You don't have permission for this page."

/** You, when an admin gave something this session doesn't honour (/me's `permissions_unverified`). */
export const UNVERIFIED = "deadwax couldn't check your account with Navidrome as you signed in, so the extra permissions an admin gave you are off until you sign in again."

/** The set /me's answer names - only names it knows, so a stray word grants nothing. An answer with no list at
 *  all is from before 2.0.0-player.61 (a session the gate kept across the upgrade): its `admin` then says it all -
 *  every permission or none. The server decides either way. */
export function permissionsOf(answer: { permissions?: unknown; admin?: unknown } | null | undefined): Permissions {
  if (!Array.isArray(answer?.permissions)) return answer?.admin === true ? ALL : NONE
  const named: unknown[] = answer.permissions
  return new Set(PERMISSIONS.filter((name) => named.includes(name)))
}

export function can(perms: Permissions, permission: Permission): boolean {
  return perms.has(permission)
}

/** Two sets the same (so a re-ask that changed nothing draws nothing). */
export function samePermissions(a: Permissions, b: Permissions): boolean {
  return a.size === b.size && PERMISSIONS.every((name) => a.has(name) === b.has(name))
}

/** Managing deadwax - You's rows and the sidebar's group: each by its permission, the group gone with none. */
export interface Managing {
  /** Albums that need a look */
  queue: boolean
  /** Library care: with Edit albums (its bulk runs) or Look after the library (Rescan, Held by nobody) */
  care: boolean
  people: boolean
  /** Server settings and the Log */
  settings: boolean
  log: boolean
  /** any of them - the group shows */
  any: boolean
}

/** `loginsOn`: People is there only with logins on - with them off, anyone who can reach deadwax is its admin,
 *  and there is nobody to manage. */
export function managing(perms: Permissions, loginsOn = true): Managing {
  const parts = {
    queue: perms.has('library'),
    care: perms.has('library') || perms.has('edit'),
    people: perms.has('people') && loginsOn,
    settings: perms.has('server'),
    log: perms.has('server'),
  }
  return { ...parts, any: Object.values(parts).some(Boolean) }
}

/** Which Managing page a kind is, and whether these permissions open it. */
export function opensPage(perms: Permissions, kind: 'queue' | 'care' | 'people' | 'settings' | 'log'): boolean {
  //? People's page itself says why with logins off - so it opens on its permission alone
  return kind === 'people' ? perms.has('people') : managing(perms)[kind]
}

/** Library care's parts: Rescan and Held by nobody are Look after the library's, the bulk runs Edit albums'. */
export interface CareParts {
  shown: boolean
  rescan: boolean
  held: boolean
  bulk: boolean
}

export function careParts(perms: Permissions): CareParts {
  const library = perms.has('library')
  const edit = perms.has('edit')
  return { shown: library || edit, rescan: library, held: library, bulk: edit }
}

/** The album page's Edit: with Edit albums or Look after the library - the editors and Get cover / CD art / lyrics
 *  inside it Edit albums', Delete Look after the library's. */
export interface AlbumEdit {
  shown: boolean
  editors: boolean
  delete: boolean
}

export function albumEdit(perms: Permissions): AlbumEdit {
  const edit = perms.has('edit')
  const library = perms.has('library')
  return { shown: edit || library, editors: edit, delete: library }
}

/** The artist page's managing: Artist images… and Which artist is this? Edit albums', Move albums to … Look after
 *  the library's. */
export interface ArtistManaging {
  images: boolean
  whichArtist: boolean
  move: boolean
  any: boolean
}

export function artistManaging(perms: Permissions): ArtistManaging {
  const edit = perms.has('edit')
  const library = perms.has('library')
  return { images: edit, whichArtist: edit, move: library, any: edit || library }
}

/** Get, the Sources sheet, Next peer and Ask again: Get albums'. */
export function gets(perms: Permissions): boolean {
  return perms.has('request')
}

/** Needs a look's count is asked for only with Look after the library (the server answers 403 otherwise). */
export function asksQueueSummary(perms: Permissions): boolean {
  return perms.has('library')
}

/** Fixing an album from Needs a look opens the editors: what its row says without Edit albums. */
export const NEEDS_EDIT = 'Fixing it needs Edit albums, which an admin hasn\'t given you.'

/**
 * One checkbox of People's Permissions, as drawn for a person: ticked or not, whether it can be changed, and the
 * line under it (the warning a tick adds, or why it is locked).
 */
export interface Checkbox {
  category: Category
  label: string
  line: string
  checked: boolean
  locked: boolean
  warning: string | null
}

/**
 * The checkboxes for a row: a Navidrome admin's all ticked and locked ("Admins can do everything."); a row People
 * refuses permissions for (yourself, NAVIDROME_USER, a reserved name - `refused`, the server's words) locked as
 * they are; anyone else's as `ticked` says - the draft, while it is being changed - each tick adding its warning.
 */
export function checkboxes(admin: boolean, refused: string | null, ticked: Readonly<Record<Category, boolean>> | null): Checkbox[] {
  return CATEGORIES.map((category) => {
    const checked = admin ? true : !!ticked?.[category]
    const warning = admin || refused ? null
      : category === 'server' && checked ? WARN_SERVER
        : category === 'library' && checked ? WARN_LIBRARY
          : category === 'request' && !checked ? WARN_NO_REQUEST
            : null
    return { category, label: LABELS[category], line: LINES[category], checked, locked: admin || !!refused, warning }
  })
}

/** What the row's Permissions say above the boxes when they can't be changed. */
export function lockedReason(admin: boolean, refused: string | null): string | null {
  if (admin) return ADMINS_EVERYTHING
  return refused
}

/** Whether a draft differs from what was saved - Save permissions is offered only then. */
export function changed(saved: Readonly<Record<Category, boolean>> | null, draft: Readonly<Record<Category, boolean>> | null): boolean {
  if (!saved || !draft) return false
  return CATEGORIES.some((category) => saved[category] !== draft[category])
}

/** What Save says once it is done. */
export function savedWords(user: string): string {
  return `Saved - ${user} has them from their next tap.`
}
