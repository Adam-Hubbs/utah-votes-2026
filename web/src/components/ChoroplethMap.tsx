import { memo, useCallback, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import { geoMercator, geoPath, type GeoProjection } from 'd3-geo'
import { zoom as d3zoom, zoomIdentity, type ZoomBehavior, type ZoomTransform } from 'd3-zoom'
import { select } from 'd3-selection'
import 'd3-transition'
import type { Feature, FeatureCollection, Geometry } from 'geojson'
import { useSize } from '../lib/hooks'
import { Tooltip } from './Tooltip'
import type { PlaceLabel } from '../types/data'

type F = Feature<Geometry, Record<string, unknown>>

interface Props {
  features: F[]
  idOf: (f: F) => string
  fill: (f: F) => string
  /** Marks units with little counted vote; drawn with a hatch overlay. */
  hatch?: (f: F) => boolean
  tooltip?: (f: F) => ReactNode
  onSelect?: (f: F | null) => void
  selectedId?: string | null
  /** Zoom to this unit id when it changes. */
  focusId?: string | null
  /** Outline-only features on top (e.g. county lines over precincts, or district lines). */
  overlay?: F[]
  overlayWidth?: number
  fitTo?: F[]
  labels?: PlaceLabel[]
  ariaLabel: string
  aspect?: number
  maxHeight?: number
  strokeWidth?: number
  strokeColor?: string
  zoomable?: boolean
}

interface PathLayerProps {
  paths: (string | null)[]
  features: F[]
  fills: string[]
  hatches: boolean[]
  strokeWidth: number
  strokeColor: string
}

const PathLayer = memo(function PathLayer({ paths, features, fills, hatches, strokeWidth, strokeColor }: PathLayerProps) {
  return (
    <g className="map-units">
      {paths.map((d, i) =>
        d ? (
          <path key={i} d={d} data-i={i} fill={fills[i]} stroke={strokeColor} strokeWidth={strokeWidth} vectorEffect="non-scaling-stroke" strokeLinejoin="round" />
        ) : null,
      )}
      {paths.map((d, i) =>
        d && hatches[i] ? <path key={`h${i}`} d={d} fill="url(#hatch)" stroke="none" pointerEvents="none" /> : null,
      )}
      <desc>{features.length} map areas</desc>
    </g>
  )
})

export function ChoroplethMap({
  features, idOf, fill, hatch, tooltip, onSelect, selectedId, focusId, overlay, overlayWidth = 1, fitTo, labels, ariaLabel,
  aspect = 1.12, maxHeight = 640, strokeWidth = 0.5, strokeColor = '#fff', zoomable = true,
}: Props) {
  const [wrapRef, { width }] = useSize<HTMLDivElement>()
  const svgRef = useRef<SVGSVGElement>(null)
  const zoomRef = useRef<ZoomBehavior<SVGSVGElement, unknown> | null>(null)
  const [tf, setTf] = useState<ZoomTransform>(zoomIdentity)
  const [hover, setHover] = useState<{ i: number; x: number; y: number } | null>(null)
  const w = Math.max(240, width || 640)

  const fitted = useMemo<{ projection: GeoProjection; h: number } | null>(() => {
    const fit = fitTo ?? features
    if (!fit.length) return null
    const fc: FeatureCollection = { type: 'FeatureCollection', features: fit }
    const pad = 6
    let proj = geoMercator().fitWidth(w - pad * 2, fc)
    let [[, y0], [, y1]] = geoPath(proj).bounds(fc)
    let h = Math.ceil(y1 - y0) + pad * 2
    if (h > maxHeight) {
      proj = geoMercator().fitHeight(maxHeight - pad * 2, fc)
      ;[[, y0], [, y1]] = geoPath(proj).bounds(fc)
      h = maxHeight
    }
    const [tx, ty] = proj.translate()
    const [[x0], [x1]] = geoPath(proj).bounds(fc)
    proj.translate([tx + (w - (x1 - x0)) / 2 - x0, ty + pad - y0 + (h - pad * 2 - (y1 - y0)) / 2])
    return { projection: proj, h: Math.max(h, 160) }
  }, [fitTo, features, w, maxHeight])
  const projection = fitted?.projection ?? null
  const h = fitted?.h ?? Math.min(maxHeight, Math.round(w * aspect))

  const path = useMemo(() => (projection ? geoPath(projection) : null), [projection])
  const paths = useMemo(() => features.map((f) => path?.(f) ?? null), [features, path])
  const overlayPaths = useMemo(() => (overlay ?? []).map((f) => path?.(f) ?? null), [overlay, path])
  const fills = useMemo(() => features.map(fill), [features, fill])
  const hatches = useMemo(() => features.map((f) => (hatch ? hatch(f) : false)), [features, hatch])
  const ids = useMemo(() => features.map(idOf), [features, idOf])

  useEffect(() => {
    const svg = svgRef.current
    if (!svg || !zoomable) return
    const z = d3zoom<SVGSVGElement, unknown>()
      .scaleExtent([1, 40])
      .extent([[0, 0], [w, h]])
      .translateExtent([[-w * 0.2, -h * 0.2], [w * 1.2, h * 1.2]])
      .filter((e: Event) => {
        const ev = e as WheelEvent & MouseEvent
        if (e.type === 'wheel') return ev.ctrlKey || ev.metaKey
        return !ev.button
      })
      .on('zoom', (e: { transform: ZoomTransform }) => setTf(e.transform))
    zoomRef.current = z
    const sel = select(svg)
    sel.call(z)
    // d3 sets touch-action:none; keep vertical page scroll usable on phones.
    svg.style.touchAction = 'pan-y'
    return () => { sel.on('.zoom', null) }
  }, [w, h, zoomable])

  const zoomBy = useCallback((k: number) => {
    const svg = svgRef.current
    if (svg && zoomRef.current) select(svg).transition().duration(250).call(zoomRef.current.scaleBy, k)
  }, [])
  const reset = useCallback(() => {
    const svg = svgRef.current
    if (svg && zoomRef.current) select(svg).transition().duration(400).call(zoomRef.current.transform, zoomIdentity)
  }, [])

  const zoomToIndex = useCallback((i: number) => {
    const svg = svgRef.current
    if (!svg || !zoomRef.current || !path) return
    const [[x0, y0], [x1, y1]] = path.bounds(features[i])
    const k = Math.min(14, 0.8 / Math.max((x1 - x0) / w, (y1 - y0) / h))
    const t = zoomIdentity.translate(w / 2, h / 2).scale(k).translate(-(x0 + x1) / 2, -(y0 + y1) / 2)
    select(svg).transition().duration(600).call(zoomRef.current.transform, t)
  }, [features, path, w, h])

  const lastFocus = useRef<string | null | undefined>(undefined)
  useEffect(() => {
    if (focusId === lastFocus.current) return
    lastFocus.current = focusId
    if (focusId) {
      const i = ids.indexOf(focusId)
      if (i >= 0) zoomToIndex(i)
    } else if (focusId === null) reset()
  }, [focusId, ids, zoomToIndex, reset])

  const locate = (e: React.PointerEvent | React.MouseEvent) => {
    const t = e.target as SVGElement
    const i = t.dataset?.i
    if (i == null) return null
    const r = wrapRef.current?.getBoundingClientRect()
    if (!r) return null
    return { i: Number(i), x: e.clientX - r.left, y: e.clientY - r.top }
  }

  const k = tf.k
  const hoverFeature = hover ? features[hover.i] : null
  const selIndex = selectedId ? ids.indexOf(selectedId) : -1

  return (
    <div className="map-wrap" ref={wrapRef}>
      <svg ref={svgRef} width={w} height={h} viewBox={`0 0 ${w} ${h}`} role="img" aria-label={ariaLabel} className="map-svg"
        onPointerMove={(e) => { if (e.pointerType !== 'touch' && e.buttons === 0) setHover(locate(e)) }}
        onPointerLeave={() => setHover(null)}
        onClick={(e) => {
          const hit = locate(e)
          if (hit) { setHover(hit); onSelect?.(features[hit.i]) } else { setHover(null); onSelect?.(null) }
        }}>
        <defs>
          <pattern id="hatch" width="5" height="5" patternUnits="userSpaceOnUse" patternTransform="rotate(45)">
            <rect width="5" height="5" fill="rgba(255,255,255,0.0)" />
            <line x1="0" y1="0" x2="0" y2="5" stroke="rgba(255,255,255,0.65)" strokeWidth="2.2" />
          </pattern>
        </defs>
        <g transform={tf.toString()}>
          <PathLayer paths={paths} features={features} fills={fills} hatches={hatches} strokeWidth={strokeWidth} strokeColor={strokeColor} />
          {overlayPaths.map((d, i) => d && <path key={i} d={d} fill="none" stroke="#121212" strokeOpacity={0.55} strokeWidth={overlayWidth} vectorEffect="non-scaling-stroke" pointerEvents="none" strokeLinejoin="round" />)}
          {selIndex >= 0 && paths[selIndex] && <path d={paths[selIndex]!} fill="none" stroke="#121212" strokeWidth={2.2} vectorEffect="non-scaling-stroke" pointerEvents="none" />}
          {hover && paths[hover.i] && <path d={paths[hover.i]!} fill="none" stroke="#121212" strokeWidth={1.6} vectorEffect="non-scaling-stroke" pointerEvents="none" />}
        </g>
        {labels && projection && (
          <g className="map-labels" pointerEvents="none">
            {labels.filter((l) => l.rank <= (k > 4 ? 5 : k > 2 ? 3 : 2)).map((l) => {
              const p = projection([l.lon, l.lat])
              if (!p) return null
              const [x, y] = tf.apply(p)
              if (x < 0 || y < 0 || x > w || y > h) return null
              return (
                <g key={l.name} transform={`translate(${x},${y})`}>
                  <circle r={2.2} fill="#121212" stroke="#fff" strokeWidth={1} />
                  <text x={5} y={3} className="map-label">{l.name}</text>
                </g>
              )
            })}
          </g>
        )}
      </svg>
      {zoomable && (
        <div className="map-controls" role="group" aria-label="Map zoom">
          <button type="button" onClick={() => zoomBy(1.8)} aria-label="Zoom in">+</button>
          <button type="button" onClick={() => zoomBy(1 / 1.8)} aria-label="Zoom out">−</button>
          <button type="button" onClick={reset} aria-label="Reset zoom" className="reset">⟲</button>
        </div>
      )}
      {hover && hoverFeature && tooltip && (
        <Tooltip x={hover.x} y={hover.y} bounds={{ width: w, height: h }}>{tooltip(hoverFeature)}</Tooltip>
      )}
    </div>
  )
}
