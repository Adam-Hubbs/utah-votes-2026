import { scaleLinear, scaleSqrt } from 'd3-scale'
import { extent, max } from 'd3-array'
import { useState } from 'react'
import { useSize } from '../lib/hooks'

export interface ScatterPoint { id: string; label: string; x: number; y: number; r: number; color: string }

interface Props {
  points: ScatterPoint[]
  xLabel: string
  yLabel: string
  xFormat: (v: number) => string
  yFormat: (v: number) => string
  height?: number
  ariaLabel: string
  onSelect?: (id: string) => void
}

export function Scatter({ points, xLabel, yLabel, xFormat, yFormat, height = 380, ariaLabel, onSelect }: Props) {
  const [ref, { width }] = useSize<HTMLDivElement>()
  const [hover, setHover] = useState<string | null>(null)
  const w = Math.max(280, width || 640)
  const m = { t: 12, r: 18, b: 44, l: 66 }
  const iw = w - m.l - m.r, ih = height - m.t - m.b
  const [x0, x1] = extent(points, (p) => p.x) as [number, number]
  const [y0, y1] = extent(points, (p) => p.y) as [number, number]
  const xs = scaleLinear().domain([x0, x1]).range([0, iw]).nice()
  const ys = scaleLinear().domain([Math.min(y0, -0.05), Math.max(y1, 0.05)]).range([ih, 0]).nice()
  const rs = scaleSqrt().domain([0, max(points, (p) => p.r) ?? 1]).range([3, 26])
  const h = points.find((p) => p.id === hover)
  const zeroY = ys(0)
  return (
    <div className="scatter" ref={ref}>
      <svg width={w} height={height} role="img" aria-label={ariaLabel}>
        <g transform={`translate(${m.l},${m.t})`}>
          {ys.ticks(5).map((t) => (
            <g key={t} transform={`translate(0,${ys(t)})`}>
              <line x2={iw} className="grid" />
              <text x={-8} dy="0.32em" textAnchor="end" className="axis-text">{yFormat(t)}</text>
            </g>
          ))}
          {xs.ticks(Math.max(3, Math.floor(iw / 90))).map((t) => (
            <text key={t} x={xs(t)} y={ih + 16} textAnchor="middle" className="axis-text">{xFormat(t)}</text>
          ))}
          <line x1={0} x2={iw} y1={zeroY} y2={zeroY} className="zero" />
          <text x={iw} y={ih + 36} textAnchor="end" className="axis-title">{xLabel} →</text>
          <text transform={`translate(${-56},0) rotate(-90)`} x={-ih} textAnchor="start" className="axis-title" dy="0.8em">{yLabel}</text>
          {[...points].sort((a, b) => b.r - a.r).map((p) => (
            <circle key={p.id} cx={xs(p.x)} cy={ys(p.y)} r={rs(p.r)} fill={p.color} fillOpacity={hover === p.id ? 0.9 : 0.5} stroke={p.color} strokeWidth={hover === p.id ? 2 : 1}
              tabIndex={0} aria-label={`${p.label}: ${xFormat(p.x)}, ${yFormat(p.y)}`}
              onPointerEnter={() => setHover(p.id)} onPointerLeave={() => setHover(null)} onFocus={() => setHover(p.id)} onBlur={() => setHover(null)}
              onClick={() => onSelect?.(p.id)} style={{ cursor: onSelect ? 'pointer' : 'default' }} />
          ))}
          {points.filter((p) => p.r > (max(points, (q) => q.r) ?? 0) * 0.12).map((p) => (
            <text key={`t${p.id}`} x={xs(p.x)} y={ys(p.y) - rs(p.r) - 3} textAnchor="middle" className="point-label" pointerEvents="none">{p.label}</text>
          ))}
        </g>
      </svg>
      {h && (
        <div className="chart-tip" style={{ left: Math.min(w - 180, Math.max(8, m.l + xs(h.x) + 14)), top: Math.max(4, m.t + ys(h.y) - 56) }}>
          <div className="chart-tip-date">{h.label}</div>
          <div className="chart-tip-row"><span>{xLabel}</span><b>{xFormat(h.x)}</b></div>
          <div className="chart-tip-row"><span>{yLabel}</span><b>{yFormat(h.y)}</b></div>
        </div>
      )}
    </div>
  )
}
