/**
 * Artist credits, as the vanilla half needs them.
 *
 * Its own module for the same reason sort.mjs is: main.js touches the DOM at module scope, so
 * nothing can import it to test it, and these decide what a download's FOLDER is called - which
 * is exactly the kind of thing that must not drift from its TypeScript twin in silence.
 * ui/test/credits.sim.cjs loads this file and ui/src/lib/release.ts side by side and holds the
 * two to the same answers.
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
// Third copy of this rule, and they must agree: creditName() in ui/src/lib/release.ts and
// credit_name() in src/artists.py. One of them names a folder, another writes the tag inside it.
export function getArtistNames(artistCredit) {
    if (!artistCredit || !artistCredit.length) return 'N/A';
    return artistCredit
        .map(ac => `${ac.name || ac.artist?.name || ''}${ac.joinphrase ?? ''}`)
        .join('')
        .trim() || 'N/A';
}

// The same credit in each artist's CURRENT name, keeping the credit's own join phrases - so a
// split stays a split and a feature stays a feature, only the names are brought up to date.
// '' rather than 'N/A' when there is nothing: this names a folder, and the caller falls back to
// the credit instead of filing an album under "N/A".
//
// Mirrors currentName() in ui/src/lib/release.ts.
export function getCurrentArtistNames(artistCredit) {
    return (artistCredit || [])
        .map(ac => `${ac.artist?.name || ac.name || ''}${ac.joinphrase ?? ''}`)
        .join('')
        .trim();
}

// Every artist id in a credit, in the order credited. Mirrors creditIds()/credit_ids().
export function getArtistIds(artistCredit) {
    const ids = [];
    for (const entry of artistCredit || []) {
        const id = entry.artist?.id;
        if (id && !ids.includes(id)) ids.push(id);
    }
    return ids;
}

// ------------------------------------------------------------------ one rule about tracks
//
// Here for the same reason as the credit helpers: main.js builds a download's payload with it,
// and flattenTracks() in ui/src/lib/release.ts builds the editor's with its TypeScript twin,
// isVideoTrack() - ui/test/credits.sim.cjs asks both the same cases.
//
// A track that never arrives as an audio file: one on a video medium, or of a recording
// MusicBrainz marks as video. Marked `video` on the payload so the "already have it" checks
// leave it out (store_index.audio_tracks) - otherwise a CD+DVD deluxe held whole could never
// read as complete. Only formats that are video whatever is on them: a plain "DVD" or "DVD-R"
// may be DVD-Audio, so it counts only by its recording's own flag. (Getting it wrong the other
// way - an audio track taken for video - would call a part held complete and refuse a download.)
const VIDEO_FORMATS = new Set([
    'DVD-Video', 'Blu-ray', 'Blu-ray-R', 'HD-DVD', 'VHS', 'VCD', 'SVCD', 'Betamax', 'LaserDisc',
    'CED', 'UMD', 'DualDisc (DVD-Video side)',
]);

export function isVideoTrack(medium, track) {
    return track?.recording?.video === true || VIDEO_FORMATS.has(medium?.format || '');
}
