/**
 * A tab that isn't built into the app yet, saying so plainly: Search and Requests are on the main
 * page for now, and this is the way there. They arrive in later steps, Requests and then Search;
 * nothing here pretends to be them meanwhile.
 *
 * The link opens the main page BESIDE the app - a new tab in a browser - so music playing here
 * carries on: followed in the same page it would unload the player, and the queue with it. From
 * the home-screen app it is outside the app's scope (`/`, where the app is `/player/`), so iOS
 * opens it outside the app, in Safari or a browser view over it (not yet seen on the phone).
 */
export function Placeholder({ title, what }: { title: string; what: string }) {
  return (
    <section class="app-placeholder">
      <header class="pl-large-header">
        <h1 class="pl-large-title">{title}</h1>
      </header>
      <div class="app-card app-placeholder-body">
        <p class="app-placeholder-lead">On the main page for now</p>
        <p class="app-placeholder-text">{what}</p>
        <a class="app-button" href="/" target="_blank" rel="noopener">
          Open the main page
        </a>
      </div>
    </section>
  )
}
