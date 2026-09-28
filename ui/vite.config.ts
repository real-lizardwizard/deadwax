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
 */
export default defineConfig({
  plugins: [preact()],

  build: {
    outDir: '../interface/dist',
    emptyOutDir: true,
    sourcemap: true,

    rollupOptions: {
      // Two pages, two entries: the main interface, and the player at /player/. Named so each
      // lands at a fixed filename its hand-written page can name; code they share (preact, the
      // HTTP helpers) is split into a hashed chunk both load.
      input: {
        'deadwax-ui': 'src/main.tsx',
        'deadwax-player': 'src/player/main.tsx',
      },
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
        chunkFileNames: 'assets/[name]-[hash].js',
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
})
