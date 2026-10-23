import { defineConfig } from 'vite'
import preact from '@preact/preset-vite'

/**
 * Vite root for the app.
 *
 * This is deliberately NOT an HTML build. The pages are hand-written - the app's at
 * `interface/player/index.html`, served at /player/ (`/` sends the browser there since
 * 2.0.0-player.66, when the main page retired) - and each loads the bundle produced here by its
 * fixed name. So the build's input is `src/player/main.tsx`, not an `index.html`. The app has no
 * harness; it is checked through the real app after a build.
 *
 * The turntable's test bench at /player/lab/ (2.0.0-player.36) is a second page, built by a SECOND pass
 * (`vite build --mode lab`, which `npm run build` runs after the first) into the same folder: it shares
 * the deck and the turntable with the player, and built beside it rollup would split what they share
 * into chunks of their own - changing what the app's page loads. Built alone it carries its own copy,
 * and the app's bundle is what it would be without it.
 */

//? The app at /player/
const APP_INPUTS = {
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
      // One entry per pass - the app's, then the bench's - named so each lands at a fixed
      // filename its hand-written page can name.
      input: mode === 'lab' ? LAB_INPUTS : APP_INPUTS,
      output: {
        // The entry filenames are stable and unhashed because static, hand-written pages
        // (`interface/player/index.html`, `interface/player/lab/index.html`) have to reference
        // them by name. That makes them mutable URLs, which is exactly why `RevalidateInterfaceAssets`
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
}))
