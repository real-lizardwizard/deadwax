/**
 * Artist credits, as the vanilla half needs them.
 *
 * Its own module for the same reason sort.mjs is: main.js touches the DOM at module scope, so
 * nothing can import it to test it. Until 2.0.0-player.15 these decided what a download's FOLDER
 * was called; since then a download's payload is built from their TypeScript twins
 * (ui/src/lib/releasePayload.ts, the one builder, which main.js reaches through the bridge), and
 * main.js uses these only to DRAW - the card's credit, and the "in your library" match by name -
 * so a drift between the two copies would mark a card wrong, never file an album under a second
 * folder. ui/test/credits.sim.cjs still loads this file and ui/src/lib/release.ts side by side and
 * holds the two to the same answers. (getArtistIds, which only the payload builders used, went with
 * them; the sim checks it isn't here.)
 *
 * Two different names come out of one credit, and they are not interchangeable:
 *
 *   getArtistNames()        what the release was CREDITED to, as printed on the sleeve. What a
 *                           stranger on Soulseek typed into their folder name, so it is what the
 *                           search asks for and what the matcher compares against.
 *   getCurrentArtistNames() who the release is BY, in each artist's CURRENT name. What the album
 *                           is filed under, so that one artist is one folder however many names
 *                           their records were credited to over the years.
 *
 * Ye is credited "Kanye West" on Donda and "Ye" on BULLY. Filing by the credit put those in two
 * folders; filing by the current name puts both in Ye/.
 */

// The join phrases ARE the punctuation MusicBrainz intends: " / " for a split, " & " for a
// collaboration, " feat. " for a guest spot. Joining on ", " instead - which this did - invents
// punctuation and turns a duet into what reads as two separate acts.
//
// The twin of creditName() in ui/src/lib/release.ts, and the two must agree: that one names what a
// download is searched for and tagged with (lib/releasePayload.ts), this one draws the card's credit
// (and is a name its "in your library" match tries).
export function getArtistNames(artistCredit) {
    if (!artistCredit || !artistCredit.length) return 'N/A';
    return artistCredit
        .map(ac => `${ac.name || ac.artist?.name || ''}${ac.joinphrase ?? ''}`)
        .join('')
        .trim() || 'N/A';
}

// The same credit in each artist's CURRENT name, keeping the credit's own join phrases - so a
// split stays a split and a feature stays a feature, only the names are brought up to date.
// '' rather than 'N/A' when there is nothing, and the caller falls back to the credit.
//
// Mirrors currentName() in ui/src/lib/release.ts, which names a download's folder (through
// lib/releasePayload.ts) and seeds the editor's; this one is a name the "in your library" match tries.
export function getCurrentArtistNames(artistCredit) {
    return (artistCredit || [])
        .map(ac => `${ac.artist?.name || ac.name || ''}${ac.joinphrase ?? ''}`)
        .join('')
        .trim();
}
