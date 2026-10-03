import { useEffect, useMemo, useState } from 'preact/hooks'

import { getArtistFacts } from '../api/musicbrainz'
import { storeAlbum } from '../api/store'
import { cardArtist, sameName, type AboutAlbumFields, type AboutDetails } from '../lib/aboutRows'
import { artistMbid } from '../lib/artistPage'
import { latestOnly } from '../lib/latest'
import type { QueueTrack } from '../lib/playQueue'
import { artistAlbums, songDetails, type ArtistWithAlbums } from '../player/api'
import { ownedNow } from './useOwned'

/** How long Info holds the song's and the store's answers back for the other: about as long as it
 *  takes to slide up, so both are usually drawn together before a finger can reach a card. */
export const INFO_SETTLE_MS = 500

/**
 * What Info > About asks for as it opens (2.0.0-player.17), for the song playing - see
 * lib/aboutRows.ts for what it draws of each:
 *
 *  - the song as Navidrome has it NOW (getSong): its play count and writers, which the album answer
 *    it was played from holds only as they were at the tap;
 *  - the store's folder of its album (the id bridge, GET /store/album by Navidrome's album id):
 *    "This pressing: …" and the folder;
 *  - the artist the card goes to (getArtist): how many albums of theirs you have, and their
 *    MusicBrainz id - Navidrome's, else what /library/owned's folders say, when the library has been
 *    asked already - and then who they are (MusicBrainz's light facts). The song's own artist, or the
 *    album's when that is them (aboutRows.ts's cardArtist); two artists of different names and ids
 *    are both asked about, and the album's is the card's only when their MusicBrainz ids are one -
 *    a renamed artist's old credit, never a compilation's Various Artists (review).
 *
 * Asked only while Info is open, again for another song: one latestOnly() for the song, so a song
 * changing under an open Info never has the last one's details drawn for it. The song's and the
 * store's answers - lines in the song's and the album's cards, above the artist's - are held back
 * until both have answered or INFO_SETTLE_MS has gone, so a card doesn't grow under a finger
 * reaching for the one below it (review); the artist's land as they come, growing only the last
 * card. A failure leaves its lines out, as everything Navidrome doesn't send is.
 */
export function useInfoDetails(open: boolean, track: QueueTrack | null, album: AboutAlbumFields | null): AboutDetails | null {
  const [details, setDetails] = useState<{ songId: string; details: AboutDetails } | null>(null)
  const requests = useMemo(latestOnly, [])
  const songId = track?.id ?? null
  const albumId = track?.albumId ?? null
  const albumSong = album?.song?.find((each) => each.id === songId) ?? null
  const songArtistId = albumSong?.artistId || null
  const albumArtistId = album?.artistId || null

  useEffect(() => {
    if (!open || !songId) return
    const request = requests.begin()
    const signal = request.signal
    const put = (more: AboutDetails) => {
      if (!request.current()) return
      setDetails((before) => ({ songId, details: { ...(before?.songId === songId ? before.details : {}), ...more } }))
    }

    //? the song's and the store's answers, held until both are in or the wait is over
    let held: AboutDetails = {}
    let holding = true
    const out = { song: true, store: !!albumId }
    const release = () => {
      if (!holding) return
      holding = false
      put(held)
    }
    const timer = setTimeout(release, INFO_SETTLE_MS)
    const land = (which: 'song' | 'store', more: AboutDetails) => {
      if (!request.current()) return
      out[which] = false
      if (!holding) put(more)
      else {
        held = { ...held, ...more }
        if (!out.song && !out.store) {
          clearTimeout(timer)
          release()
        }
      }
    }

    const names = { song: albumSong?.artist || track?.artist || '', album: album?.artist ?? '' }
    const facts = (artist: ArtistWithAlbums) => {
      const mbid = artistMbid(artist, artist.album ?? [], ownedNow()?.index ?? null)
      if (mbid) getArtistFacts(mbid, signal).then((found) => put({ facts: found }), () => {})
    }
    const theirs = (id: string, artist: ArtistWithAlbums) => ({ id, ...(artist.albumCount !== undefined ? { albumCount: artist.albumCount } : {}) })
    //? the artist the card goes to - and, two of them, which: the album's only when it is the song's
    const lookUp = (songArtist: string | null) => {
      const card = cardArtist(names, { song: songArtist, album: albumArtistId })
      if (!card) return
      const two = !!songArtist && !!albumArtistId && card === songArtist && songArtist !== albumArtistId
      if (!two) {
        artistAlbums(card, signal).then((artist) => {
          put({ artist: theirs(card, artist) })
          facts(artist)
        }, () => {})
        return
      }
      Promise.all([artistAlbums(songArtist, signal), artistAlbums(albumArtistId!, signal).catch(() => null)]).then(([own, filedUnder]) => {
        const index = ownedNow()?.index ?? null
        const ownId = artistMbid(own, own.album ?? [], index)
        const filedId = filedUnder ? artistMbid(filedUnder, filedUnder.album ?? [], index) : null
        const one = !!ownId && ownId === filedId
        const [id, artist] = one ? [albumArtistId!, filedUnder!] : [songArtist, own]
        put({ artist: theirs(id, artist) })
        facts(artist)
      }, () => {})
    }

    songDetails(songId, signal).then(
      (song) => {
        land('song', { song })
        //? no album answer in hand to say who the song is by: getSong says
        if (!songArtistId && !albumArtistId && song.artistId) lookUp(song.artistId)
      },
      () => land('song', {}),
    )
    if (albumId) storeAlbum({ navidrome_id: albumId }, signal).then((store) => land('store', { store }), () => land('store', {}))
    //? names that differ with no song artist known: the card still goes to the album's artist
    //? (aboutRows), but says nothing about them - what it would say might be another artist's
    const unsure = !songArtistId && !!albumArtistId && !!names.album && !sameName(names.album, names.song)
    if ((songArtistId || albumArtistId) && !unsure) lookUp(songArtistId)
    return () => {
      clearTimeout(timer)
      requests.supersede()
    }
  }, [open, songId, albumId, songArtistId, albumArtistId])

  return details && details.songId === songId ? details.details : null
}
