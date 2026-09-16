import { useCallback, useEffect, useRef, useState } from 'preact/hooks'

import { Loading } from './Loading'

export interface ViewerImage {
  label: string
  /** Tried in order; the next is used when one fails to load. */
  sources: string[]
  /** Said in place of the image when none of the sources load. */
  missing?: string
}

interface Props {
  /** One image, or two to compare side by side. */
  images: ViewerImage[]
  onClose: () => void
  /**
   * An optional decision to make from here, e.g. "Use this cover" in the metadata editor.
   *
   * `requires` is the index of the image the action acts on. The button stays disabled until
   * that image has actually LOADED - offering "replace with this cover" beside a pane that says
   * there is no cover would be offering a request that can only 404.
   */
  action?: {
    label: string
    title?: string
    busy?: boolean
    requires?: number
    onClick: () => void
  } | undefined
}

const MAX_ZOOM = 8
/** A wheel notch is about 100 units, so one notch is about 16%. */
const WHEEL_ZOOM = 0.0015

/** How the image sits in its pane: 1 is fitted, and x/y move it from the centre in px. */
interface View {
  zoom: number
  x: number
  y: number
}

const FIT: View = { zoom: 1, x: 0, y: 0 }

interface Size {
  width: number
  height: number
}

/**
 * Cover art at full size, one image or two side by side.
 *
 * Exists for the metadata editor's "which cover do I keep" decision, where the thumbnails could
 * not answer the actual question. Two covers of the same record usually look identical at 72px;
 * what differs is resolution and scan quality, which only shows at full size. So each image
 * reports its real pixel dimensions, the larger is marked, and a click shows it at actual size.
 *
 * Escape is caught in the CAPTURE phase and stopped there. The editor underneath listens for
 * Escape on the document to close itself, and without this one keypress would close both.
 */
export function ArtViewer({ images, onClose, action }: Props) {
  const [sizes, setSizes] = useState<(Size | null)[]>(() => images.map(() => null))

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key !== 'Escape') return
      event.stopPropagation()
      event.preventDefault()
      onClose()
    }
    window.addEventListener('keydown', onKeyDown, true)
    return () => window.removeEventListener('keydown', onKeyDown, true)
  }, [onClose])

  //? only once every image has reported in, and only a strict winner - two equal covers get no
  //? badge, rather than one of them being called larger by the order they loaded in
  const pixels = sizes.map((size) => (size ? size.width * size.height : 0))
  const best = Math.max(...pixels)
  const largest =
    images.length > 1 && sizes.every(Boolean) && pixels.filter((p) => p === best).length === 1
      ? pixels.indexOf(best)
      : -1

  return (
    <div id="art-viewer" role="dialog" aria-modal="true" aria-label="Cover art" onClick={onClose}>
      <div class="art-viewer-frame" onClick={(event) => event.stopPropagation()}>
        <div class="window-titlebar">
          <span class="window-title">Cover art</span>
          <button type="button" class="window-close" title="Close (Esc)" onClick={onClose}>✕</button>
        </div>

        <div class={`art-viewer-panes count-${images.length}`}>
          {images.map((image, index) => (
            <ArtPane
              key={`${index}:${image.sources.join('|')}`}
              image={image}
              largest={index === largest}
              onSize={(size) =>
                setSizes((current) => current.map((s, i) => (i === index ? size : s)))}
            />
          ))}
        </div>

        <div class="art-viewer-footer">
          <span class="text white-tertiary art-viewer-hint">
            Click to zoom in where you point · scroll to zoom · drag to move.
          </span>
          {action && (
            <button
              type="button"
              class="win-button is-default"
              disabled={action.busy || (action.requires !== undefined && !sizes[action.requires])}
              title={action.requires !== undefined && !sizes[action.requires]
                ? 'There is no cover to save until it has loaded'
                : action.title}
              onClick={action.onClick}
            >
              {action.busy ? <Loading label="Saving" /> : action.label}
            </button>
          )}
          <button type="button" class="win-button" onClick={onClose}>Close</button>
        </div>
      </div>
    </div>
  )
}

function ArtPane(
  { image, largest, onSize }:
  { image: ViewerImage; largest: boolean; onSize: (size: Size | null) => void },
) {
  const [attempt, setAttempt] = useState(0)
  const [state, setState] = useState<'loading' | 'loaded' | 'failed'>('loading')
  const [size, setSize] = useState<Size | null>(null)
  const [view, setView] = useState<View>(FIT)
  const [panning, setPanning] = useState(false)
  const stageRef = useRef<HTMLDivElement>(null)
  const imgRef = useRef<HTMLImageElement>(null)

  const src = image.sources[attempt]
  const failed = state === 'failed' || !src

  //? a pane with nothing to show still has to report, or the comparison waits on it forever
  useEffect(() => {
    if (failed) onSize(null)
  }, [failed])

  /**
   * Hold the image inside its pane: it can be moved until an edge reaches the middle, no further.
   *
   * Letting it go anywhere means a cover dragged off the side leaves an empty pane and no way to
   * tell where it went.
   */
  const clamp = useCallback((next: View): View => {
    const img = imgRef.current
    const stage = stageRef.current
    if (!img || !stage) return next

    //? SIZE from the offset properties. The image is the thing being transformed, so its rect is
    //? the ZOOMED box and would multiply the zoom back in - see CLAUDE.md on transformed boxes
    const spareX = Math.max(0, (img.offsetWidth * next.zoom - stage.clientWidth) / 2)
    const spareY = Math.max(0, (img.offsetHeight * next.zoom - stage.clientHeight) / 2)

    return {
      zoom: next.zoom,
      x: Math.min(spareX, Math.max(-spareX, next.x)),
      y: Math.min(spareY, Math.max(-spareY, next.y)),
    }
  }, [])

  /**
   * Zoom about a point on screen, so whatever is under the cursor stays under the cursor.
   *
   * Zooming about the centre instead is what made this useless for the job it exists for: the
   * corner of a sleeve you want a closer look at walks off the pane as it grows.
   */
  const zoomAt = useCallback((clientX: number, clientY: number, factor: number) => {
    setView((current) => {
      const stage = stageRef.current
      if (!stage) return current

      const zoom = Math.min(MAX_ZOOM, Math.max(1, current.zoom * factor))
      if (zoom === current.zoom) return current

      //? POSITION from the rect - the stage is not transformed, only the image inside it is
      const rect = stage.getBoundingClientRect()
      //? the image is centred in the stage, so the centre is what its translation is measured from
      const px = clientX - (rect.left + rect.width / 2)
      const py = clientY - (rect.top + rect.height / 2)
      const scale = zoom / current.zoom

      //? the point under the cursor sits at (px - x) / zoom in the image; hold it still
      return clamp({ zoom, x: px - (px - current.x) * scale, y: py - (py - current.y) * scale })
    })
  }, [clamp])

  //? a listener of our own, because Preact's onWheel cannot be marked non-passive - and a passive
  //? one may not preventDefault, which would scroll the page behind the viewer instead of zooming
  useEffect(() => {
    const stage = stageRef.current
    if (!stage) return undefined

    const onWheel = (event: WheelEvent) => {
      event.preventDefault()
      zoomAt(event.clientX, event.clientY, Math.exp(-event.deltaY * WHEEL_ZOOM))
    }

    stage.addEventListener('wheel', onWheel, { passive: false })
    return () => stage.removeEventListener('wheel', onWheel)
  }, [zoomAt])

  //? another image starts again; a window that changed shape under a zoomed one is pulled back in
  useEffect(() => setView(FIT), [src])
  useEffect(() => {
    const onResize = () => setView((current) => clamp(current))
    window.addEventListener('resize', onResize)
    return () => window.removeEventListener('resize', onResize)
  }, [clamp])

  /**
   * Drag to move the image; a press that never travels is a click, which zooms.
   *
   * One gesture has to decide which it was, so nothing moves until the pointer has gone a few
   * pixels - the same rule the column headers use. Without it a click with a shaky hand nudges
   * the image instead of zooming, and neither gesture feels like it was heard.
   */
  const startPan = (event: PointerEvent) => {
    if (event.button !== 0) return
    event.preventDefault()

    const img = event.currentTarget as HTMLImageElement
    const startX = event.clientX
    const startY = event.clientY
    let lastX = startX
    let lastY = startY
    let moved = false

    img.setPointerCapture(event.pointerId)

    const move = (e: PointerEvent) => {
      if (!moved && Math.abs(e.clientX - startX) < 4 && Math.abs(e.clientY - startY) < 4) return
      if (!moved) {
        moved = true
        setPanning(true)
      }

      const dx = e.clientX - lastX
      const dy = e.clientY - lastY
      lastX = e.clientX
      lastY = e.clientY
      setView((current) => clamp({ zoom: current.zoom, x: current.x + dx, y: current.y + dy }))
    }

    const up = (e: PointerEvent) => {
      img.removeEventListener('pointermove', move)
      img.removeEventListener('pointerup', up)
      img.removeEventListener('pointercancel', up)
      setPanning(false)
      if (moved) return

      if (view.zoom > 1) {
        setView(FIT)
        return
      }

      //? 1:1 where that is bigger, but never less than a doubling: this album's cover is 600px
      //? shown at 570, so "actual size" alone zoomed it by five per cent and read as nothing
      //? happening at all. A click is a step you can see; the wheel is for the sizes between.
      const actual = imgRef.current?.offsetWidth
        ? imgRef.current.naturalWidth / imgRef.current.offsetWidth
        : 2
      zoomAt(e.clientX, e.clientY, Math.max(2, actual))
    }

    img.addEventListener('pointermove', move)
    img.addEventListener('pointerup', up)
    img.addEventListener('pointercancel', up)
  }

  return (
    <figure class="art-viewer-pane">
      <figcaption class="art-viewer-caption">
        <span class="art-viewer-label">{image.label}</span>
        {size && <span class="art-viewer-dims">{size.width} × {size.height} px</span>}
        {view.zoom > 1 && <span class="art-viewer-dims">×{view.zoom.toFixed(1)}</span>}
        {largest && <span class="art-viewer-largest" title="More pixels than the other one">Larger</span>}
      </figcaption>

      <div
        ref={stageRef}
        class={`art-viewer-stage${view.zoom > 1 ? ' is-zoomed' : ''}${panning ? ' is-panning' : ''}`}
      >
        {src && !failed && (
          <img
            ref={imgRef}
            src={src}
            alt={image.label}
            draggable={false}
            title={view.zoom > 1 ? 'Drag to move · click to fit' : 'Click to zoom in · scroll to zoom'}
            style={`transform:translate(${view.x}px,${view.y}px) scale(${view.zoom})`
              + (state === 'loaded' ? '' : ';visibility:hidden')}
            onPointerDown={(event) => startPan(event as unknown as PointerEvent)}
            onLoad={(event) => {
              const el = event.currentTarget as HTMLImageElement
              const measured = { width: el.naturalWidth, height: el.naturalHeight }
              setSize(measured)
              onSize(measured)
              setState('loaded')
            }}
            onError={() => {
              if (attempt + 1 < image.sources.length) setAttempt((n) => n + 1)
              else setState('failed')
            }}
          />
        )}

        {state === 'loading' && src && (
          <div class="art-viewer-status"><Loading label="Loading full size" /></div>
        )}

        {failed && (
          <div class="art-viewer-status text white-tertiary">{image.missing ?? 'No image'}</div>
        )}
      </div>
    </figure>
  )
}
