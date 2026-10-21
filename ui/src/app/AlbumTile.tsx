import { isNew } from '../lib/myLibrary'
import { dropPrefetch, prefetchAlbum, type Album } from '../player/api'
import { Cover } from '../player/Cover'

/** What is new in your library, as lib/myLibrary.ts newMarks makes it - handed down by the shelf, made once. */
export type Marks = { ids: Set<string>; releases: Set<string> }

/**
 * One album's tile (2.0.0-player.59, the one tile the Library's shelf and its root's Recently added draw): the
 * cover, the title, the artist and - with logins on - the New mark of an album new in your library until you open
 * it. It OPENS its album - asking for its songs as the finger lands, so Play is usually ready by the time the page
 * opens; a press that turns into a scroll lets go of the ask (api.ts). Nothing here plays (the gesture rule).
 */
export function AlbumTile({ album, marks, onOpen }: {
  album: Album
  marks: Marks
  onOpen: (album: Album) => void
}) {
  return (
    <button
      type="button"
      class="pl-album"
      onPointerDown={() => prefetchAlbum(album.id)}
      onPointerCancel={() => dropPrefetch(album.id)}
      onClick={() => onOpen(album)}
    >
      <Cover id={album.coverArt} size={400} class="pl-album-cover" />
      <span class="pl-album-title">{album.name}</span>
      <span class="pl-album-artist">{album.artist}</span>
      {isNew(marks, album) && (
        <span class="pl-album-new">
          New<span class="app-visually-hidden"> in your library</span>
        </span>
      )}
    </button>
  )
}
