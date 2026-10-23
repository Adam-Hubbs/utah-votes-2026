import { line } from 'd3-shape'
import { scaleLinear } from 'd3-scale'
import { extent } from 'd3-array'

export function Sparkline({ values, width = 80, height = 24, color = 'var(--ink-2)', domain }: { values: number[]; width?: number; height?: number; color?: string; domain?: [number, number] }) {
  if (values.length < 2) return <svg width={width} height={height} aria-hidden />
  const [lo, hi] = domain ?? (extent(values) as [number, number])
  const x = scaleLinear().domain([0, values.length - 1]).range([2, width - 3])
  const y = scaleLinear().domain([lo, hi === lo ? lo + 1 : hi]).range([height - 3, 3])
  const d = line<number>().x((_, i) => x(i)).y((v) => y(v))(values) ?? ''
  const last = values[values.length - 1]
  return (
    <svg width={width} height={height} aria-hidden className="sparkline">
      <path d={d} fill="none" stroke={color} strokeWidth={1.6} strokeLinejoin="round" strokeLinecap="round" />
      <circle cx={x(values.length - 1)} cy={y(last)} r={2.4} fill={color} />
    </svg>
  )
}
