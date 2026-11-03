import { useMemo, useState } from 'react'
import { scaleLinear, scaleSqrt, scaleTime } from 'd3-scale'
import { area, curveMonotoneX, line } from 'd3-shape'
import { bisector, extent, max, min } from 'd3-array'
import { timeFormat } from 'd3-time-format'
import { useSize } from '../lib/hooks'
import { fmtDayYear } from '../lib/format'
import { TooltipHeader, TooltipNote, TooltipRow } from './Tooltip'

export interface TPoint { x: Date; y: number; lo?: number; hi?: number }
export interface TDot { x: Date; y: number; n?: number; tip?: string }
export interface TSeries {
  id: string
  label: string
  /** Short label used at the line end. */
  endLabel?: string
  color: string
  line: TPoint[]
  dots?: TDot[]
  dashed?: boolean
}

interface Props {
  series: TSeries[]
  height?: number
  yDomain?: [number, number]
  yFormat?: (v: number) => string
  valueFormat?: (v: number) => string
  xDomain?: [Date, Date]
  marker?: { x: Date; label: string }
  ariaLabel: string
  endLabels?: boolean
  /** Extra line in tooltip, e.g. n polls. */
  hint?: (x: Date) => string | null
  minSpanDays?: number
  xTickFormat?: (d: Date) => string
  tipDateFormat?: (d: Date) => string
}

const tickFmt = timeFormat('%b %-d')
const tickFmtYear = timeFormat('%b %Y')

export function PollChart({
  series, height = 340, yDomain, yFormat = (v) => `${v}%`, valueFormat = (v) => v.toFixed(1), xDomain, marker, ariaLabel, endLabels = true, hint, minSpanDays = 14, xTickFormat, tipDateFormat = fmtDayYear,
}: Props) {
  const [ref, { width }] = useSize<HTMLDivElement>()
  const [hover, setHover] = useState<Date | null>(null)
  const w = Math.max(280, width || 640)
  const narrow = w < 520
  const shorten = (t: string) => (narrow && t.length > 7 ? `${t.slice(0, 6)}…` : t)
  const m = { t: 12, r: endLabels ? (narrow ? 92 : 128) : 16, b: 26, l: 38 }
  const iw = w - m.l - m.r
  const ih = height - m.t - m.b

  const allX = series.flatMap((s) => [...s.line.map((p) => p.x), ...(s.dots ?? []).map((d) => d.x)])
  const xs = useMemo(() => {
    if (xDomain) return xDomain
    const [a, b] = extent(allX) as [Date | undefined, Date | undefined]
    if (!a || !b) return [new Date(), new Date()] as [Date, Date]
    const end = marker ? new Date(Math.max(b.getTime(), marker.x.getTime())) : b
    const spanMs = end.getTime() - a.getTime()
    const edge = minSpanDays < 1 ? Math.max(spanMs * 0.03, 60000) : 86400000
    const pad = Math.max(0, minSpanDays * 86400000 - spanMs) / 2
    return [new Date(a.getTime() - pad - edge), new Date(end.getTime() + pad + edge)] as [Date, Date]
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [series, xDomain, marker, minSpanDays])

  const ys = useMemo(() => {
    if (yDomain) return yDomain
    const vals = series.flatMap((s) => [...s.line.flatMap((p) => [p.y, p.lo ?? p.y, p.hi ?? p.y]), ...(s.dots ?? []).map((d) => d.y)])
    const lo = min(vals) ?? 0, hi = max(vals) ?? 100
    const pad = (hi - lo) * 0.08
    return [Math.max(0, Math.floor((lo - pad) / 5) * 5), Math.ceil((hi + pad) / 5) * 5] as [number, number]
  }, [series, yDomain])

  const x = scaleTime().domain(xs).range([0, iw])
  // Day-only labels repeat across years (two "Jan 1"s), so long spans get the year instead.
  const fmtTick = xTickFormat ?? (+xs[1] - +xs[0] > 300 * 864e5 ? tickFmtYear : tickFmt)
  const y = scaleLinear().domain(ys).range([ih, 0]).nice(5)
  const maxN = max(series.flatMap((s) => (s.dots ?? []).map((d) => d.n ?? 0))) ?? 1
  const r = scaleSqrt().domain([0, maxN || 1]).range([2.5, 8.5])

  const lineGen = line<TPoint>().x((p) => x(p.x)).y((p) => y(p.y)).curve(curveMonotoneX)
  const areaGen = area<TPoint>().x((p) => x(p.x)).y0((p) => y(p.lo ?? p.y)).y1((p) => y(p.hi ?? p.y)).curve(curveMonotoneX)

  const ends = series
    .filter((s) => s.line.length)
    .map((s) => ({ s, last: s.line[s.line.length - 1] }))
    .sort((a, b) => b.last.y - a.last.y)
  const placed: { s: TSeries; yPos: number; v: number }[] = []
  let prev = -Infinity
  for (const e of ends) {
    const target = y(e.last.y)
    const pos = Math.max(target, prev + 13)
    placed.push({ s: e.s, yPos: pos, v: e.last.y })
    prev = pos
  }
  const over = placed.length ? placed[placed.length - 1].yPos - (ih - 4) : 0
  if (over > 0) placed.forEach((p) => (p.yPos -= over))

  const xTicks = x.ticks(Math.max(2, Math.floor(iw / 95)))
  const yTicks = y.ticks(5)

  const times = useMemo(() => [...new Set(series.flatMap((s) => s.line.map((p) => p.x.getTime())))].sort((a, b) => a - b), [series])
  const bis = bisector((t: number) => t).center

  const onMove = (e: React.PointerEvent<SVGRectElement>) => {
    const rect = e.currentTarget.getBoundingClientRect()
    const dt = x.invert(e.clientX - rect.left)
    if (!times.length) return
    setHover(new Date(times[bis(times, dt.getTime())]))
  }

  const hoverRows = hover
    ? series.map((s) => {
        const pts = s.line
        if (!pts.length) return null
        const idx = bisector((p: TPoint) => p.x.getTime()).center(pts, hover.getTime())
        const p = pts[idx]
        return { s, p, exact: p.x.getTime() === hover.getTime() }
      }).filter((v): v is NonNullable<typeof v> => v != null).sort((a, b) => b.p.y - a.p.y)
    : []

  return (
    <div className="poll-chart" ref={ref}>
      <svg width={w} height={height} role="img" aria-label={ariaLabel}>
        <g transform={`translate(${m.l},${m.t})`}>
          {yTicks.map((t) => (
            <g key={t} transform={`translate(0,${y(t)})`}>
              <line x2={iw} className="grid" />
              <text x={-8} dy="0.32em" textAnchor="end" className="axis-text">{yFormat(t)}</text>
            </g>
          ))}
          {xTicks.map((t) => (
            <text key={t.getTime()} x={x(t)} y={ih + 18} textAnchor="middle" className="axis-text">{fmtTick(t)}</text>
          ))}
          <line x1={0} x2={iw} y1={ih} y2={ih} className="axis" />

          {marker && (
            <g transform={`translate(${x(marker.x)},0)`}>
              <line y2={ih} className="marker" />
              <text y={10} x={-5} textAnchor="end" className="marker-text">{marker.label}</text>
            </g>
          )}

          {series.map((s) => (
            s.line.length > 1 && s.line.some((p) => p.lo != null) ? (
              <path key={`a-${s.id}`} d={areaGen(s.line) ?? ''} fill={s.color} fillOpacity={0.14} />
            ) : null
          ))}
          {series.map((s) => (s.dots ?? []).map((d, i) => (
            <circle key={`d-${s.id}-${i}`} cx={x(d.x)} cy={y(d.y)} r={r(d.n ?? 0)} fill={s.color} fillOpacity={0.3} stroke={s.color} strokeOpacity={0.75} strokeWidth={0.8}>
              {d.tip && <title>{d.tip}</title>}
            </circle>
          )))}
          {series.map((s) => (
            s.line.length > 1 ? (
              <path key={`l-${s.id}`} d={lineGen(s.line) ?? ''} fill="none" stroke={s.color} strokeWidth={2.4} strokeLinecap="round" strokeDasharray={s.dashed ? '5 4' : undefined} />
            ) : s.line.length === 1 ? (
              <g key={`p-${s.id}`}>
                {s.line[0].lo != null && s.line[0].hi != null && <line x1={x(s.line[0].x)} x2={x(s.line[0].x)} y1={y(s.line[0].lo)} y2={y(s.line[0].hi)} stroke={s.color} strokeWidth={5} strokeOpacity={0.2} strokeLinecap="round" />}
                <circle cx={x(s.line[0].x)} cy={y(s.line[0].y)} r={4.5} fill={s.color} stroke="#fff" strokeWidth={1.5} />
              </g>
            ) : null
          ))}

          {endLabels && placed.map((p) => {
            const last = p.s.line[p.s.line.length - 1]
            return (
              <g key={`e-${p.s.id}`}>
                <line x1={x(last.x) + 4} x2={iw + 6} y1={y(last.y)} y2={p.yPos} stroke={p.s.color} strokeOpacity={0.5} strokeWidth={0.8} />
                <text x={iw + 9} y={p.yPos} dy="0.32em" className="end-label" fill={p.s.color === '#E3B505' || p.s.color === '#F0CB45' ? '#8a6900' : p.s.color}>
                  <tspan fontWeight={700}>{valueFormat(p.v)}</tspan>
                  <tspan dx={4}>{shorten(p.s.endLabel ?? p.s.label)}</tspan>
                </text>
              </g>
            )
          })}

          {hover && (
            <g pointerEvents="none">
              <line x1={x(hover)} x2={x(hover)} y1={0} y2={ih} className="crosshair" />
              {hoverRows.map((row) => <circle key={row.s.id} cx={x(row.p.x)} cy={y(row.p.y)} r={4} fill={row.s.color} stroke="#fff" strokeWidth={1.5} />)}
            </g>
          )}
          <rect width={iw} height={ih} fill="transparent" onPointerMove={onMove} onPointerLeave={() => setHover(null)} style={{ touchAction: 'pan-y' }} />
        </g>
      </svg>
      {hover && hoverRows.length > 0 && (
        <div className="chart-tip" style={{ left: Math.min(w - 190, Math.max(m.l, m.l + x(hover) + 12)), top: 8 }}>
          <TooltipHeader title={tipDateFormat(hover)} />
          {hoverRows.map((row) => (
            <TooltipRow key={row.s.id} color={row.s.color} label={row.s.label} value={valueFormat(row.p.y)} />
          ))}
          {hint?.(hover) && <TooltipNote>{hint(hover)}</TooltipNote>}
        </div>
      )}
    </div>
  )
}
