import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'

/**
 * Vite root for the Preact migration.
 *
 * This is deliberately NOT an HTML build. While the port is in progress the vanilla
 * `interface/index.html` is still the page users get, and it loads the bundle produced here
 * as one extra module script. So the build inputs are `src/main.tsx` - and, for the player's
 * own page at /player/, `src/player/main.tsx` - not `index.html`, and `index.html` in this
 * directory exists only as a dev harness for the main interface (see the file itself). The
 * player has no harness; it is checked through the real app on 8080 after a build.
 *
 * When the migration finishes and Vite owns the main page, let it build `index.html` normally -
 * but keep the player's entry beside it: dropping `rollupOptions.input` outright would drop the
 * player. See docs/FRONTEND-MIGRATION.md.
 *
 * The turntable's test bench at /player/lab/ (2.0.0-player.36) is a third page, built by a SECOND pass
 * (`vite build --mode lab`, which `npm run build` runs after the first) into the same folder: it shares
 * the deck and the turntable with the player, and built beside it rollup would split what they share
 * into chunks of their own - changing what the app's page loads. Built alone it carries its own copy,
 * and the app's bundle is what it would be without it.
 */

//? The app's two pages: the main interface, and the player at /player/
const APP_INPUTS = {
  'deadwax-ui': 'src/main.tsx',
  'deadwax-player': 'src/player/main.tsx',
}
//? ...and the turntable's test bench at /player/lab/, a pass of its own
const LAB_INPUTS = {
  'deadwax-lab': 'src/lab/main.tsx',
}

export default defineConfig(({ mode }) => ({
  plugins: [preact()],

  build: {
    outDir: '../interface/dist',
    //? the bench's pass adds to what the app's left
    emptyOutDir: mode !== 'lab',
    sourcemap: true,

    rollupOptions: {
      // Two pages, two entries: the main interface, and the player at /player/. Named so each
      // lands at a fixed filename its hand-written page can name; code they share (preact, the
      // HTTP helpers) is split into a hashed chunk both load. (The bench's pass: one entry.)
      input: mode === 'lab' ? LAB_INPUTS : APP_INPUTS,
      output: {
        // The entry filenames are stable and unhashed because static, hand-written pages
        // (`interface/index.html`, `interface/player/index.html`) have to reference them by
        // name. That makes them mutable URLs, which is exactly why `RevalidateInterfaceAssets`
        // in src/api/app.py has to send `no-cache` for them - otherwise upgrading the container
        // leaves people on the old bundle, which is the "I upgraded and nothing changed" bug
        // that middleware exists to prevent.
        entryFileNames: '[name].js',
        // Split chunks and assets keep their hashes and are served immutable. Same file
        // contents always mean the same URL, so caching them hard is safe.
        chunkFileNames: mode === 'lab' ? 'assets/lab-[name]-[hash].js' : 'assets/[name]-[hash].js',
        assetFileNames: 'assets/[name]-[hash][extname]',
      },
    },
  },

  server: {
    proxy: {
      // dev against the real FastAPI backend, so no CORS handling is needed. Not the string
      // shorthand: that sets changeOrigin, rewriting Host to 127.0.0.1:8080 while the browser's
      // Origin still says localhost:5173 - and since 1.0.1 the backend refuses a write whose
      // Origin names another host (src/api/same_origin.py). Keeping the Host keeps them agreeing.
      '/deadwax': { target: 'http://127.0.0.1:8080', changeOrigin: false },
      // the dev harness reuses the real stylesheet and fonts rather than a copy that can
      // drift out of sync with what production actually serves
      '/styles': 'http://127.0.0.1:8080',
      '/assets': 'http://127.0.0.1:8080',
    },
  },
}))
